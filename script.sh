#!/bin/bash 	
#Taking inputs from User
echo -n "Enter AWS Profile: "	
read AWSPROFILE 
echo -n "Enter AWS Region: "
read AWSREGION
echo -n "Enter AWS LogGroupName: "
read LOGGROUP
echo -n "Enter File size in BYTES to split log files: " 
read split_file_size     #5242880(5MB) 10485760(10MB) in bytes
#If User want to provide specific stream/s of the LogGroup 	
OUTSTREAMS=
while :
do
    echo -n "Enter stream: "
    read stream
	if [ -z "$stream" ]; then
	break
	else
	OUTSTREAMS+=" $stream"  
	fi
done	
#If User don't provide any Logstream this will bring all the stream/s of the LogGroup provided
function logstreamsname {
  aws --profile $AWSPROFILE --region $AWSREGION logs describe-log-streams \
    --order-by LastEventTime --log-group-name $LOGGROUP \
    --output text | while read -a st; do 
      len=${#st[@]}
	  for (( i=6; i<$len; i+=8 )); do echo "${st[$i]}" ; done
	  done 
}
#Based to the LogGroupName and stream/s selected this will dump logs from cloudwatch to files
function dumpstreams {
	streams=
	if [ -z "$OUTSTREAMS" ]; then
		streams=$(logstreamsname)
	else
		streams=$OUTSTREAMS
	fi
	count=1 #counter for renaming splited files 
	PrevToken=0 
	echo ""
	echo "------------------------Dumping Logs Started-------------------------"
    echo ""
	for stream in $streams 
	do
	  echo "Dumping Logs from this stream: $stream"
		filename=log-$stream
		aws --profile em-shared-sandbox --region us-east-2 logs get-log-events \
        --start-from-head  \
        --log-group-name LISAppLogError --log-stream-name "$stream" > $filename.json
		while true; do
			NextToken=$(grep -oP '(?<="nextForwardToken": ")[^"]*' $filename.json | tail -1) 
			if [ $NextToken != $PrevToken  ] && [ $(stat --format=%s "$filename.json") -lt $split_file_size ]; then
				aws --profile $AWSPROFILE --region $AWSREGION logs get-log-events \
				--next-token $NextToken --start-from-head \
				--log-group-name $LOGGROUP --log-stream-name "$stream" >> $filename.json
				PrevToken=$NextToken
			elif [ $NextToken != $PrevToken  ] && [ $(stat --format=%s "$filename.json") -ge $split_file_size ]; then
				filename=log-$stream
				filename=$filename-$count
				aws --profile $AWSPROFILE --region $AWSREGION logs get-log-events \
				--next-token $NextToken --start-from-head \
				--log-group-name $LOGGROUP --log-stream-name "$stream" >> $filename.json
				PrevToken=$NextToken
				let count++
			else
				echo "Log Download Complete"
				echo "---------------------------------------------------------------------"
				filename=log-$stream
				count=1
				break
			fi
		done
   done
}
dumpstreams
