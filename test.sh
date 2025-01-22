AO_ID=$1
FUNCTION_NAME=$2
DATA=$(cat data/$2.txt | jq -c . | jq -R -s .)
echo $FUNCTION_NAME
echo $DATA
echo $AO_ID
echo "Send({Target=\"$AO_ID\",Action=\"$FUNCTION_NAME\",Data=$DATA})"