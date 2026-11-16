#!/bin/bash
# HealthLab Part 12: delete everything the manual guide created, in reverse order of creation.
# Finds each resource by its guide name, shows the list, asks before deleting. Anything already
# gone is skipped, so it is safe to rerun (a rerun that finds nothing = all clean).
# Run in CloudShell:  bash <(curl -sL https://raw.githubusercontent.com/haru-mishi/healthlab/main/scripts/cleanup.sh)
set -uo pipefail
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
q() { local v; v=$(aws "$@" --output text 2>/dev/null); [ -n "$v" ] && echo "$v" || echo None; }

RULE=$(q events list-rules --name-prefix healthlab-daily-reminder --query "Rules[?Name=='healthlab-daily-reminder'].Name | [0]")
API=$(q apigatewayv2 get-apis --query "Items[?Name=='healthlab-api'].ApiId | [0]")
POOL=None
for p in $(q cognito-idp list-user-pools --max-results 60 --query "UserPools[].Id"); do
  [ "$(q cognito-idp list-user-pool-clients --user-pool-id "$p" --query "UserPoolClients[?ClientName=='healthlab-web'].ClientId | [0]")" != None ] && { POOL=$p; break; }
done
FNS=""
for n in analyzer api subscribe reminder; do
  aws lambda get-function --function-name "healthlab-$n" > /dev/null 2>&1 && FNS+="healthlab-$n "
done
LOGS=$(q logs describe-log-groups --log-group-name-prefix /aws/lambda/healthlab- --query "logGroups[].logGroupName")
TOPIC=$(q sns list-topics --query "Topics[?ends_with(TopicArn,':healthlab-alerts')].TopicArn | [0]")
TABLE=$(q dynamodb describe-table --table-name HealthReports --query Table.TableName)
B=$(q s3api list-buckets --query "Buckets[?starts_with(Name,'healthlab-uploads-')].Name | [0]")
APP=$(q amplify list-apps --query "apps[?name=='healthlab'].appId | [0]")

echo "Found (None = already gone):"
echo "  EventBridge rule : $RULE"
echo "  API Gateway      : $API"
echo "  Cognito pool     : $POOL"
echo "  Lambda           : ${FNS:-None}"
echo "  Log groups       : $(echo $LOGS)"
echo "  SNS topic        : $TOPIC"
echo "  DynamoDB table   : $TABLE"
echo "  S3 bucket        : $B"
echo "  Amplify app      : $APP"
if [ "$RULE$API$POOL$TOPIC$TABLE$B$APP$LOGS" = NoneNoneNoneNoneNoneNoneNoneNone ] && [ -z "$FNS" ]; then
  echo "Nothing left to delete. Remove the Gemini key in AI Studio, then End Lab."; exit 0
fi
read -rp 'Type yes to delete all of the above: ' A
[ "$A" = yes ] || { echo "Cancelled, nothing deleted."; exit 1; }

step() { echo "- $1"; }
if [ "$RULE" != None ]; then
  step "EventBridge $RULE"
  IDS=$(q events list-targets-by-rule --rule "$RULE" --query "Targets[].Id")
  [ "$IDS" != None ] && aws events remove-targets --rule "$RULE" --ids $IDS > /dev/null
  aws events delete-rule --name "$RULE"
fi
[ "$API" != None ] && step "API Gateway $API" && aws apigatewayv2 delete-api --api-id "$API"
if [ "$POOL" != None ]; then
  step "Cognito $POOL (domain, deletion protection, pool)"
  D=$(q cognito-idp describe-user-pool --user-pool-id "$POOL" --query UserPool.Domain)
  [ "$D" != None ] && aws cognito-idp delete-user-pool-domain --user-pool-id "$POOL" --domain "$D"
  aws cognito-idp update-user-pool --user-pool-id "$POOL" --deletion-protection INACTIVE
  aws cognito-idp delete-user-pool --user-pool-id "$POOL"
fi
for f in $FNS; do step "Lambda $f"; aws lambda delete-function --function-name "$f"; done
if [ "$LOGS" != None ]; then
  for g in $LOGS; do step "Log group $g"; aws logs delete-log-group --log-group-name "$g"; done
fi
[ "$TOPIC" != None ] && step "SNS $TOPIC" && aws sns delete-topic --topic-arn "$TOPIC"
[ "$TABLE" != None ] && step "DynamoDB $TABLE" && aws dynamodb delete-table --table-name "$TABLE" > /dev/null
[ "$B" != None ] && step "S3 $B (empty, then delete)" && aws s3 rb "s3://$B" --force > /dev/null
[ "$APP" != None ] && step "Amplify $APP" && aws amplify delete-app --app-id "$APP" > /dev/null

echo "Done. Run this script once more: it should say 'Nothing left to delete'."
echo "Then remove the Gemini key at https://aistudio.google.com/apikey and click End Lab."
