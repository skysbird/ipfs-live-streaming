#!/bin/bash

# Load settings

# Create directory for HLS content
#rm -rf ./hls/*
#cd ./hls



what="live"
key="key"
RESTARTED="1"


func() {
    echo "Usage:"
    echo "[-i source file] [-k ipns key] [-w workdir]"
    exit -1
}
 
upload="false"
 
while getopts 'i:k:u:w:' OPT; do
    case $OPT in
        i) sfile="$OPTARG";;
        k) key="$OPTARG";;
        w) workdir="$OPTARG";;
        ?) func;;
    esac
done

workdir=$(echo -n $sfile | md5sum|awk '{print $1}')
realdir=tmp/$workdir
echo $realdir
echo "init...."
mkdir -p $realdir
#rm -rf $workdir/*

cmd="ffmpeg -stream_loop -1 -re -i $sfile -c:v libx264  -c:a copy -maxrate 0.3M -f hls -hls_time 10 -hls_list_size 3 $realdir/live.m3u8"
echo $cmd

$cmd 1>/dev/null 2>&1 &
 
echo "tm work dir is $realdir"
cd $realdir

echo "creating stream key ...."
ipfs key rm $workdir

streamkey=$(ipfs key gen --type=rsa --size=2048 --ipns-base=b58mh  $workdir)
echo $streamkey
#streamkey="4c083e39c796d99dbd7d9fbe6085a086"
echo "your ipns streamkey is $streamkey"

ipfs key list -l --ipns-base=b58mh
a=0
while true; do
  nextfile=$(cat ${what}.m3u8 | tail -n1)
  echo $nextfile
  if [ -f "${nextfile}" ]; then
    timecode=$(grep -B1 ${nextfile} ${what}.m3u8 | head -n1 | awk -F : '{print $2}' | tr -d ,)
    if ! [ -z "${nextfile}" ]; then
      if ! [ -z "{$timecode}" ]; then
        reset_stream_marker=''
        if [[ "$(grep -B2 ${nextfile} ${what}.m3u8 | head -n1)" == "#EXT-X-DISCONTINUITY" || "${RESTARTED}" == "1" ]]; then
          reset_stream_marker=" #EXT-X-DISCONTINUITY"
          RESTARTED="0"
        fi

        # Current UTC date for the log
        time=$(date "+%F-%H-%M-%S")

        # Add ts file to IPFS
        hash=$(ipfs add -Q ${nextfile})

        if [[ -z "${hash}" ]]; then
          echo ${nextfile} Add Failed, skipping for retry
        else
          # Update the log with the future name (hash already there)
          echo added ${hash} ${nextfile} ${time}.ts ${timecode}${reset_stream_marker} >>process-stream.log

          # Remove nextfile and tmp.txt
          rm -f ${nextfile} ~/tmp.txt
          echo "#EXTM3U" >current.m3u8
          echo "#EXT-X-VERSION:3" >>current.m3u8
          echo "#EXT-X-TARGETDURATION:20" >>current.m3u8
          echo "#EXT-X-MEDIA-SEQUENCE:${a}" >>current.m3u8
          #echo "#EXT-X-PLAYLIST-TYPE:EVENT" >>current.m3u8

          tail -n 10 process-stream.log | awk '{print $6"#EXTINF:"$5",\n'${IPFS_GATEWAY}'/ipfs/"$2}' | sed 's/#EXT-X-DISCONTINUITY#/#EXT-X-DISCONTINUITY\n#/g' >>current.m3u8

          # Add m3u8 file to IPFS and IPNS publish (uncomment to enable)
          m3u8hash=$(ipfs add current.m3u8 | awk '{print $2}')
          echo "ipfs name publish --key=$workdir --ttl 1s --timeout=5s --ipns-base=b58mh $m3u8hash "
          ipfs name publish --key=$workdir --ttl 1s --timeout=5s $m3u8hash &
         
          a=$(($a+1))

          # Copy files to web server
          #cp current.m3u8 /var/www/html/live.m3u8
          #cp ~/process-stream.log /var/www/html/live.log
        fi
      fi
    fi
  else
    sleep 1
  fi
done
