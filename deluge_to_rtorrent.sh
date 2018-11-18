#!/bin/bash
torrentid=$1
torrentname=$2
torrentpath=$3

# 此腳本修改自 github.com/wseedbox/deluge-to-rtorrent
##############################################################
# Define these vars to the path where they are located
##############################################################
# 下載完成後幾秒執行轉移腳本(s)
count=1200

# deluge-console位置
dc=/usr/bin/deluge-console

# deluge_state資料夾位置
deluge_state_dir=/root/.config/deluge/state

# rtorrent_fast_resume.pl位置
rtfr=/root/rtorrent_fast_resume.pl

# 暫存資料夾位置
tmpdir=/root/tmp/deluge2rtorrent

# 檔案下載位置
torrent_download_dir=/home/Downloads

# rtorrent監視資料夾
torrent_dir=/home/mickey/rtorrent/torrents

# XMR-RPC路徑
xmlrpc=/usr/bin/xmlrpc
xmlrpc_endpoint=127.0.0.1
xmlrpc_command="${xmlrpc} ${xmlrpc_endpoint}"

# 是否有使用Racing.sh腳本(1:有 ,0:無)
Racing_Mode=1

# 開啟Racing Mode後，設定之rtorren上傳速限(KB/s)，需與Racing腳本設定相同
Racing_limit_upspeed=20480

# 非Racing Mode時，rtorren上傳速限(KB/s)
Non_Racing_limit_upspeed=76800

##############################################################

# 獲取Tracker資訊
tracker_line=$($dc info $torrentid | grep "^Tracker" | awk -F: '{print $2}' | tr -d " ")

# 特定Tracker不執行轉移，並解除限速
case "$tracker_line" in
  *flacsfor*|*hdbits*|*dmhy*|*passthepopcorn*)
    if [ $Racing_Mode = 1 ]; then
      global_up_max_rate=$($xmlrpc_command throttle.global_up.max_rate | grep integer | awk -F "64-bit integer: " '{print $2}')
      let max_rate=global_up_max_rate/1024

# 若rtorrent當前速度大於等於 Racing_limit_upspeed ，則將速度設為 Non_Racing_limit_upspeed
      if [ $max_rate = $Racing_limit_upspeed ] || [ $max_rate -gt $Racing_limit_upspeed ] || [ $max_rate = 0 ]; then
         $xmlrpc_command throttle.global_up.max_rate.set_kb "" $Non_Racing_limit_upspeed
         echo $(date +"%Y-%m-%d %H:%M:%S") >> ~/rtspeed.log
         echo "Finish Torrent: $torrentname($torrentid)" >> ~/rtspeed.log	 
		 echo "rTorrent global upload speed: $Non_Racing_limit_upspeed KB/s" >> ~/rtspeed.log	 
# 否則將速度設為當前速限的2倍
      else
         let Racing_Mode_limit2_upspeed=max_rate*2
         $xmlrpc_command throttle.global_up.max_rate.set_kb "" $Racing_Mode_limit2_upspeed
         echo $(date +"%Y-%m-%d %H:%M:%S") >> ~/rtspeed.log
         echo "Finish Torrent: $torrentname($torrentid)" >> ~/rtspeed.log	 
		 echo "rTorrent global upload speed: $Racing_Mode_limit2_upspeed KB/s" >> ~/rtspeed.log	 
      fi
    fi
    exit 0
    ;;
esac

# 下載完成後幾秒執行轉移腳本
sleep $count

# 設定標籤資訊
function set_tracker {
  case $1 in
    *alpharatio*)
   	  tracker=ar
      ;;
    *empire*|*stackoverflow*|*iptorrent*)
   	  tracker=ipt
      ;;
    *torrentleech*)
   	  tracker=tl
      ;;
   	*)
   	  tracker=$1
	  ;;
  esac
}
set_tracker $tracker_line

# 獲取Ratio資訊
ratio=$($dc info $torrentid | grep Ratio: | awk -F "Ratio: " '{print $2}')

# 測試用
#echo $tracker
#echo $ratio

# 複製Deluge種子至tmpdir資料夾
cp ${deluge_state_dir}/${torrentid}.torrent ${tmpdir}/${torrentid}.torrent

#執行rtorrent_fast_resume.pl腳本
$rtfr $torrent_download_dir ${deluge_state_dir}/${torrentid}.torrent ${tmpdir}/${torrentid}_fast.torrent
if [[ $? -ne 0 ]]; then
  echo $(date +"%Y-%m-%d %H:%M:%S") >> ~/de2rt.log
  echo "Something went wrong when converting the torrent file with $(basename ${rtfr})" >> ~/de2rt.log
  exit 0
else
  echo $(date +"%Y-%m-%d %H:%M:%S") >> ~/de2rt.log
  echo "$torrentname($torrentid) was added rTorrent fast resume data." >> ~/de2rt.log
fi

# 從Deluge刪除種子
sleep 5
$dc rm $torrentid

#將fast resume種子移至rtorrent的監視資料夾中
#$xmlrpc_command load.start ${tmpdir}/${torrentid}_fast.torrent
cp ${tmpdir}/${torrentid}_fast.torrent ${torrent_dir}/${torrentid}_fast.torrent
sleep 3

# 設定標籤資訊
#$xmlrpc_command d.custom1.set ${torrentid} ${tracker}

# 傳遞Ratio資訊到rtorrent，請與github.com/wseedbox/rutorrent-deluge-ratio搭配使用
$xmlrpc_command d.custom.set ${torrentid} deluge_ratio ${ratio}

# 刪除暫存資料夾
#/usr/bin/rm -rf $tmpdir

exit 0
