#!/usr/bin/env bash

if [ "$(whoami)" != "root" ];then
  echo "root permission need"
  exit 1
fi

while [[ $# -ge 1 ]]; do
  case $1 in
    -install )
      INSTALL=true
      shift
      ;;
    -uninstall )
      UNINSTALL=true
      shift
      ;;
    -list )
      LIST=true
      shift
      ;;
    -show )
      SHOW=true
      shift
      ;;
    -in )
      IN=true
      shift
      ;;
    -out )
      OUT=true
      shift
      ;;
    -debug )
      DEBUG=true
      shift
      ;;
    -add )
      ADD=$2
      shift 2
      ;;
    -del )
      DEL=$2
      shift 2
      ;;
    -id )
      ID=$2
      shift 2
      ;;
    -dev )
      DEV=$2
      shift 2
      ;;
    -port )
      PORT=$2
      shift 2
      ;;
    -max )
      MAX=$2
      shift 2
      ;;
    -min )
      MIN=$2
      shift 2
      ;;
    -h )
      echo "-install"
      echo "-add             ex: -add rule -port 8080 -max 1024"
      echo "-del             ex: -del rule -id 3"
      echo "-id              rule id  default 1"
      echo "-list            list rule"
      echo "-dev             Network Interface Card;  Default: First NIC"
      echo "-in              IN"
      echo "-out             OUT "
      echo "-port            port"
      echo "-max             max speed kb; 128=1M 256=2M 512=4M 1024=8M 1280=10M 2048 16M 2560=20M"
      echo "-min             default = max"
      echo "-show            show command"
      echo "-h               help info"
      shift
      exit 0
      ;;
    * )
    echo "undefined:$1"
    exit 1
    ;;
  esac
done


if [ "$DEV" == "" ];then
  DEV=$(ifconfig  | grep UP -m 1 | awk -F":" '{print $1}')
fi

if [ "$MAX" == "" ];then
    MAX=1024
fi

if [ "$MIN" == "" ];then
    MIN=$MAX
fi

if [ "$PORT" == "" ];then
    PORT=8080
fi

if [ "$INSTALL" == "true" ];then
  echo "install"
fi


if [ "$UNINSTALL" == "true" ];then
  # root handle must be 1:0
  qdiscInfo=$(tc qdisc show dev "$DEV" | grep htb)
  if [ "$qdiscInfo" != "" ];then
    cmd="tc qdisc del dev $DEV root"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd
  fi

  qdiscIngressInfo=$(tc qdisc show dev "$DEV" | grep ingress)
  if [ "$qdiscIngressInfo" != "" ];then
    cmd="tc qdisc del dev $DEV ingress"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd

    DEV=ifb0
    cmd="tc qdisc del dev $DEV root"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd

    cmd="tc qdisc del dev $DEV ingres"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd

    cmd="ip link set dev ifb0 down"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd

    cmd="modprobe -r ifb"
    if [ "$SHOW" == "true" ];then
      echo CMD : "$cmd"
    fi
    $cmd
  fi
fi



if [ "$ADD" == "rule" ];then

  if [ "$OUT" == "true" ];then
    if [ "$DEBUG" == "true" ];then
      echo "is OUT"
    fi

    # check root
    qdiscInfo=$(tc qdisc show dev $DEV | grep htb)
    if [ "$qdiscInfo" == "" ];then
      cmd="tc qdisc add dev "$DEV" root handle 1: htb"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd
    fi
    DIRECTION=sport
  fi

  if [ "$IN" == "true" ];then
    if [ "$DEBUG" == "true" ];then
      echo "is IN"
    fi

    # check ingress
    qdiscIngressInfo=$(tc qdisc show dev $DEV | grep ingress)
    if [ "$qdiscIngressInfo" == "" ];then
      cmd="tc qdisc add dev "$DEV" handle ffff: ingress"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd

      sleep 1

      DEV=ifb0
      cmd="modprobe ifb"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd

      sleep 1

      # start dev ifb0
      if [ "$DEBUG" == "true" ];then
         echo "start dev ifb0"
      fi
      cmd="ip link set dev ifb0 up"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd

      sleep 1

      #  redirect dev ifb0
      if [ "$DEBUG" == "true" ];then
        echo "redirect dev ifb0"
      fi
      cmd="tc filter add dev "$DEV" parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd

      cmd="tc qdisc add dev "$DEV" root handle 1: htb"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
      fi
      $cmd
    fi

    DEV=ifb0
    DIRECTION=dport

  fi

  cmd="tc filter show dev $DEV"
  filterInfo=$($cmd)
  filterClassIdList=($(echo "$filterInfo" | grep flowid | awk '{print $21}'))
  filterNum=${#filterClassIdList[@]}

  # check id
  if [ "$ID" != "" ];then
    for ((i=1; i<=filterNum;i++))
    do
      classId=${filterClassIdList[$i-1]}
      classIdSub=$(echo "$classId" | awk -F":" '{print $2}')
      if [[ $classIdSub -eq $ID ]];then
        echo "ID:$ID already exists"
        exit 0
      fi
    done
  fi

  # auto generate id if id is empty
  if [ "$ID" == "" ];then
    ID=0
    cmd="tc filter show dev $DEV"
    filterInfo=$($cmd)
    filterClassIdList=($(echo "$filterInfo" | grep flowid | awk '{print $21}'))
    filterNum=${#filterClassIdList[@]}
    for ((i=1; i<=filterNum;i++))
    do
      classId=${filterClassIdList[$i-1]}
      classIdSub=$(echo "$classId" | awk -F":" '{print $2}')
      if [ "$classIdSub" -gt $ID ];then
        ID=$classIdSub
      fi
    done
    ID=$((ID+1))
  fi

  cmd="tc class add dev "$DEV" parent 1:0 classid 1:$ID htb rate "$MIN"kbps ceil "$MAX"kbps"
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
     $cmd
  fi

  cmd="tc filter add dev "$DEV" parent 1:0 prio 1 protocol ip u32 match ip $DIRECTION $PORT 0xffff flowid 1:$ID"
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
     $cmd
  fi
fi

if [ "$DEL" == "rule" ];then
  if [ "$OUT" == "true" ];then
    if [ "$DEBUG" == "true" ];then
      echo "is OUT"
    fi
  fi

  if [ "$IN" == "true" ];then
    if [ "$DEBUG" == "true" ];then
      echo "is IN"
    fi
    DEV=ifb0
  fi
  # first order
  cmd="tc filter show dev $DEV"
  filterInfo=$($cmd)
  filterIdList=($(echo "$filterInfo" | grep flowid | awk '{print $12}'))
  filterNum=${#filterIdList[@]}
  filterClassIdList=($(echo "$filterInfo" | grep flowid | awk '{print $21}'))
  for ((i=1; i<=filterNum;i++))
  do
    classId=${filterClassIdList[$i-1]}
    classIdSub=$(echo "$classId" | awk -F":" '{print $2}')
    if [ "$classIdSub" == $ID ];then
      classId2filterId=${filterIdList[$i-1]}
      cmd="tc filter del dev $DEV parent 1: protocol ip prio 1  handle $classId2filterId u32"
      if [ "$SHOW" == "true" ];then
        echo CMD : "$cmd"
        exit 0
      fi
      $cmd
    fi
  done
  cmd="tc class del dev $DEV parent $1:0 classid 1:$ID"
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
     $cmd
  fi
fi


if [ "$LIST" == "true" ];then
  echo "------------- OUT ----------------"
  qdiscInfo=$(tc qdisc show | grep htb)
#  if [ "$qdiscInfo" == "" ];then
#     exit 0
#  fi

  rootId=$(echo "$qdiscInfo" | awk '{print $3}')
  #echo  "$qdiscInfo " | awk '{print $3}'

  cmd="tc filter show dev $DEV"
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
    filterInfo=$($cmd)
    filterIdList=($(echo "$filterInfo" | grep flowid | awk '{print $12}'))
    filterNum=${#filterIdList[@]}
    filterPortList=($(echo "$filterInfo" | grep match | awk '{print $2}'))
    filterClassIdList=($(echo "$filterInfo" | grep flowid | awk '{print $21}'))
  fi

  cmd="tc class show dev "$DEV""
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
    classInfo=$($cmd)
    classIdList=($(echo "$classInfo" | awk '{print $3}'))
    #classMinList=($(echo "$classInfo" | awk '{print $8}'))
    classMaxList=($(echo "$classInfo" | awk '{print $10}'))
  fi
  for ((i=1; i<=filterNum;i++))
  do
    port16=$(echo "${filterPortList[$i-1]}" | awk -F"0000/" '{print $1}')
    port10=$((16#$port16))
    classId=${filterClassIdList[$i-1]}
    classIdSub=$(echo "$classId" | awk -F":" '{print $2}')
    echo "$classIdSub: <---port:$port10 - max: ${classMaxList[$i-1]} "
  done


  # For Input
  echo "------------- IN ----------------"
  qdiscIngressInfo=$(tc qdisc show | grep ingress)
  if [ "$qdiscIngressInfo" == "" ];then
     exit 0
  fi

  # default ifb0
  DEV=ifb0
  qdiscVirtualInfo=$(tc qdisc show dev $DEV)

  cmd="tc filter show dev $DEV"
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
    filterInfo=$($cmd)
    filterIdList=($(echo "$filterInfo" | grep flowid | awk '{print $12}'))
    filterNum=${#filterIdList[@]}
    filterPortList=($(echo "$filterInfo" | grep match | awk '{print $2}'))
    filterClassIdList=($(echo "$filterInfo" | grep flowid | awk '{print $21}'))
  fi

  cmd="tc class show dev "$DEV""
  if [ "$SHOW" == "true" ];then
    echo CMD : "$cmd"
  else
    classInfo=$($cmd)
    classIdList=($(echo "$classInfo" | awk '{print $3}'))
    #classMinList=($(echo "$classInfo" | awk '{print $8}'))
    classMaxList=($(echo "$classInfo" | awk '{print $10}'))
  fi

  for ((i=1; i<=filterNum;i++))
  do
    port16=$(echo "${filterPortList[$i-1]}" | awk -F"/0000" '{print $1}')
    port10=$((16#$port16))
    classId=${filterClassIdList[$i-1]}
    classIdSub=$(echo "$classId" | awk -F":" '{print $2}')
    echo "$classIdSub: --->port:$port10 - max: ${classMaxList[$i-1]} "
  done
fi
