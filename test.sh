#!/bin/bash

if [ ! -f "/root/backup/test.txt" ]
then
touch /root/backup/test.txt
fi

for((i=0;i<10;i++))
do
curl http://192.168.138.200 >>  /root/backup/test.txt
sleep 1
done
