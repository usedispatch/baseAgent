FUNCTION_NAME="AddTodo"
DATA=$(cat data.txt | jq -c . | jq -R -s .)
AO_ID=$1
echo $FUNCTION_NAME
echo $DATA
echo $AO_ID
echo "Send({\"Target\":\"$AO_ID\",\"Action\":\"$FUNCTION_NAME\",\"Data\":$DATA})"