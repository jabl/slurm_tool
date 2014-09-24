#!/bin/bash
#
# Frontend wrapper for the most often needed but
# un{usable,readable,informative} SLURM commands.
# tapio.leipala@aalto.fi

# format variables for customizing output
#
# for example, if 'slurm partition' should differentiate node features, add 
#     fmt_s_parts="%10P %.11l %.15F %10f %N"
# into the following file
if [ -n "$XDG_CONFIG_HOME" ]
then
    user_vars=$XDG_CONFIG_HOME/slurmvars
else
    user_vars=$HOME/.config/slurmvars
fi

# these can be overridden in ~/.slurmvars
fmt_quick="%9P %.4C %.5D %.7m %.8f %.10q %.10T %r"
fmt_user="%18i %9P %14j %.11M %.16S %.8T %R"
fmt_short="%8Q %9P %.8u [ %.4C x %5D %7m : %8f ] %.11l %.8T %r"
fmt_shorter="%9P %.8u [ %.4C x %5D %7m : %8f & %6q ] %.11l %.8T %r"
fmt_full="%Q %i %P %j %u %C %D %m %f %q %h %t %M %l %R"
fmt_s_parts="%10P %.11l %.15F %10f %N"
fmt_s_nodes="%.5D %.10T %.4c %.7m %10f %N"
fmt_s_prio="%.8u %.10Y %.10F %.10J %.10A %.10Q %.12P"
fmt_s_prio_all="%.8u %.12i %.10Y %.10F %.10J %.10A %.10Q %.12P"
fmt_s_prio_user="%.12i %.10Y %.10F %.10J %.10A %.10Q %.12P"
if [ -r $user_vars ]; then source $user_vars; fi

fmt_s_stat="jobid,avevmsize,averss,maxvmsize,maxrss,ntasks,nodelist"
fmt_a_hist="jobid,jobname,start,reqmem,maxrss,totalcpu,elapsed,ntasks,alloccpus,nnodes,exitcode,state,user,nodelist"
fmt_a_qos="Format=Priority,Name,MaxWall,GrpCPUs,MaxCPUsPerUser"
fmt_a_user="WithAssoc"
fmt_top="%u|%j|%C|%m"

cmd_watch="/usr/bin/watch -n 15 --no-title"
cmd_queue_size="squeue -S T,P,u,m,C,D,l,t -o"
cmd_queue_prio="squeue -S T,P,p,u -o"
cmd_queue_job="squeue -S T,P,-S,-i -o"
cmd_jobs="scontrol show job"
cmd_share="sshare -al"
cmd_qos="sacctmgr -n -p show qos -o"
cmd_qos_u="sacctmgr -n -p show user"
cmd_user="sacctmgr show user"
cmd_stat="sstat -Pano"
cmd_hist="sacct -s ca,cd,f,to,nf,s -Pno"
cmd_nodes="sinfo -Neo"
cmd_parts="sinfo -o"
cmd_prio="sprio -o"
cmd_dead="sinfo -R"
cmd_top="squeue -hao"
merge="/usr/bin/uniq -c"
clean="/usr/bin/column -t"
prune="/bin/grep -v '\ 0\ \ '"

function usage {
    self=`basename $0`
    cat <<EOF

Show or watch job queue:
 $self [watch] queue     show own jobs
 $self [watch] q <user>  show user's jobs
 $self [watch] quick     show quick overview of own jobs
 $self [watch] shorter   sort and compact entire queue by job size
 $self [watch] short     sort and compact entire queue by priority
 $self [watch] full      show everything
 $self [w] [q|qq|ss|s|f] shorthands for above!

 $self qos               show job service classes
 $self top [queue|all]   show summary of active users

Show detailed information about jobs:
 $self prio [all|short]  show priority components
 $self j|job <jobid>     show everything else
 $self steps <jobid>     show memory usage of running srun job steps

Show usage and fair-share values from accounting database:
 $self h|history <time>  show jobs finished since, e.g. "1day" (default)
 $self shares

Show nodes and resources in the cluster:
 $self p|partitions      all partitions
 $self n|nodes           all cluster nodes
 $self c|cpus            total cpu cores in use
 $self cpus <partition>  cores available to partition, allocated and free
 $self cpus jobs         cores/memory reserved by running jobs
 $self cpus queue        cores/memory required by pending jobs

EOF

    if [ "$USER" = "root" ]; then
	cat <<EOF
Admin commands:
 $self top
 $self history 30days -u user
 $self history 1hour -a -r gpu
 $self dead
 $self qos <user>
 $self user <user>
EOF
    fi
    exit 0
}

function commands {
    case $1 in 
	w|watch)
	    shift
	    test -z "$1" && usage
	    watch=true
	    commands "$@"
	    ;;
	q|queue)
	    if [ "$2" ]; then
		cmd="$cmd_queue_job '$fmt_user' -u $2"
	    else
		cmd="$cmd_queue_job '$fmt_user' -u $USER"
	    fi
	    ;;
	qq|quick)
	    if [ "$2" ]; then
		cmd="$cmd_queue_size '$fmt_quick' -u $2 | $merge | $clean"
	    else
		cmd="$cmd_queue_size '$fmt_quick' -u $USER | $merge | $clean"
	    fi
	    ;;
	s|short)
	    header=true
	    if [ "$2" ]; then
              cmd="$cmd_queue_prio '$fmt_short' -p $2 | $merge"
	    else
              cmd="$cmd_queue_prio '$fmt_short' | $merge"
	    fi
	    ;;
	ss|shorter)
	    header=true
	    if [ "$2" ]; then
	      cmd="$cmd_queue_size '$fmt_shorter' -p $2 | $merge"
	    else
	      cmd="$cmd_queue_size '$fmt_shorter' | $merge"
	    fi
	    ;;
	f|full)
	    if [ "$2" ]; then
		cmd="$cmd_queue_job '$fmt_full' -u $2 | $clean"
	    else
		cmd="$cmd_queue_job '$fmt_full' | $clean"
	    fi
	    ;;
	prio)
	    case $2 in
		s|short)
		    cmd="$cmd_prio '$fmt_s_prio' | $merge | $clean"
		    ;;
		a|all)
		    cmd="$cmd_prio '$fmt_s_prio_all' | $clean"
		    ;;
		*)
		    if [ "$2" ]; then
			cmd="$cmd_prio '$fmt_s_prio_user' -u $2"
		    else
			cmd="$cmd_prio '$fmt_s_prio_user' -u $USER"
		    fi
		    ;;
	    esac
	    ;;
	shares)
	    cmd="$cmd_share | $prune"
	    ;;	    
	qos)
	    if [ $2 ]; then
		userqos "$2"
	    else
		qosqueue
	    fi
	    ;;	    
	user)
	    cmd="$cmd_user $2 '$fmt_a_user'"
	    ;;	    
	top)
	    top_users "$2"
	    ;;	    
	steps)
	    shift
	    jobstat "$@"
	    ;;
	h|history)
	    shift
	    jobacct "$@"
	    ;;	    
	dead)
	    cmd="$cmd_dead"
	    ;;	    
	j|job)
	    shift
	    cmd="$cmd_jobs $@"
	    ;;	    
	n|nodes)
	    if [ $2 ]; then
		cmd="$cmd_nodes '$fmt_s_nodes' -n $2"
	    else
		cmd="$cmd_nodes '$fmt_s_nodes'"
	    fi
	    ;;	    
	p|partitions)
	    cmd="$cmd_parts '$fmt_s_parts'"
	    ;;	    
	c|cpus)
	    if [ $# == 1 ]; then
		rescount RUNNING ;
	    else
	    	shift
	    	case $1 in
			q|queue) rescount PENDING ;;
			j|jobs)  rescount RUNNING ;;
			*)       corealloc "$@" ;;
	    	esac
	    fi
	    exit 0
	    ;;
	*)
	    usage
	    ;;
    esac
}

function jobstat {
    echo "JobID       AvgVMem  AvgRes    MaxVMem  MaxRes  Tasks  Nodelist"
    eval "$cmd_stat $fmt_s_stat -j $@" | awk 'BEGIN{FS="|"}
  {printf "%-10s %-8.8s %-7.7s   %-8.8s %-7.7s %6s  %-20s\n", $1,
    ($2>0) ? ($2~/G/)?
        sprintf("%7.0fM",gensub(/G/,"",1,$2)*1024):
        sprintf("%7.0fM",gensub(/K/,"",1,$2)/1024) : "-",
    ($3>0) ? ($3~/G/)?
        sprintf("%6.0fM",gensub(/G/,"",1,$3)*1024):
        sprintf("%6.0fM",gensub(/K/,"",1,$3)/1024) : "-",
    ($4>0) ? ($4~/G/)?
        sprintf("%7.0fM",gensub(/G/,"",1,$4)*1024):
        sprintf("%7.0fM",gensub(/K/,"",1,$4)/1024) : "-",
    ($5>0) ? ($5~/G/)?
        sprintf("%6.0fM",gensub(/G/,"",1,$5)*1024):
        sprintf("%6.0fM",gensub(/K/,"",1,$5)/1024) : "-",
    $6,$7,$8 }'
}

function jobacct {
    if [ "$COLUMNS" -lt 130 ]; then
	echo -n "Warning: output will not fit."
	printf "%$((${COLUMNS}-29))s\n\n" "drag here to widen terminal->"
    fi
    if [ "$1" ]; then
	datespec="$1"
	shift
    else
	datespec="1days"
    fi
    date=$(date -d "-$datespec" '+%Y-%m-%dT%H:%M')
    echo "JobID         JobName              Start            ReqMem  MaxRSS\
 TotalCPUTime    WallTime Tasks CPU Ns Exit State Nodes"
    eval "$cmd_hist $fmt_a_hist -S $date $@" | awk 'BEGIN{FS="|"}
  {printf "%-13s %-20.20s %-14.14s %8.8s %7.7s %12s %11s %5s %3.3s %-2.2s%5s %-5.4s %s\n",
    ($1~/batch/) ? "└─batch" : ($1~/\.[0-9]/)?"  "$1:""$1,
    ($1~/batch/) ? "*" : $2,
    gensub(/T/," ",1,substr($3,6)),
     $4,
#    ($4>0) ? ($4~/G/)?
#        sprintf("%7.0fM",gensub(/G/,"",1,$4)*1024):
#        sprintf("%7.0fM",gensub(/K/,"",1,$4)/1024) : "-",
    ($5>0) ? ($5~/G/)?
        sprintf("%6.0fM",gensub(/G/,"",1,$5)*1024):
        sprintf("%6.0fM",gensub(/K/,"",1,$5)/1024) : "-",
    $6,$7, ($8>0)?$8:"none", $9,$10, $11,$12,$14
  }'
}

function corealloc {
    if [ ! "$1" ]; then show="*"; fi
    echo "Partition  Nodes  Cores  Alloc  Free"
    for part in "$show" "$@"; do
	if [ "$part" = "*" ]; then
	    nodespec=$(sinfo -hro '%N')
	    nodes=$(sinfo -hro '%D')
	else
	    nodespec=$(sinfo -hro '%N' -p "$part")
	    nodes=$(sinfo -hro '%D' -p "$part")
	fi
	if [ ! "$nodes" ]; then
	    continue 1
	fi
	let c=$(scontrol show node $nodespec | \
	    awk 'BEGIN{RS=" ";FS="="} /CPUTot/{i+=$2} END{print i}')
	let a=$(scontrol show node $nodespec | \
	    awk 'BEGIN{RS=" ";FS="="} /CPUAlloc/{i+=$2} END{print i}')
	let f=$c-$a
	printf "%-10s %5i  %5i  %5i %5i\n" "$part" "$nodes" $c $a $f
    done
}

# fmt_top="%u|%j|%C|%m"
function top_users {
    case $1 in
	all)    state="R,PD,S" ;;
	queue)  state="PENDING" ;;
	*)      state="RUNNING" ;;
    esac
    echo "      User  Jobs x Cores   Mem(GB) GB/c  Jobs"
    eval "$cmd_top '$fmt_top'" -t $state | awk -v w=$COLUMNS 'BEGIN{FS="|"}
  {jn[$1]+=1; j[$1]=j[$1]" "$2"["$3"]"; c[$1]+=$3; ($4~/K/)?m[$1]+=$3*$4*1000:m[$1]+=$3*$4;}
  END{for(u in c){printf "%10s %5d x %-5d %8.1f %5.1f  %s\n",
    u,jn[u],c[u],m[u]/1024,m[u]/c[u]/1024,substr(j[u],2,w-42);}}' | sort -nrk4
}

function qosqueue {
    echo "Service Class   Prio    TimeLimit Cores/User  Cores  Jobs/Queue (# cores)"
    eval "$cmd_qos $fmt_a_qos" | sort -nr | awk 'BEGIN{FS="|";
    while ("squeue -t r,pd -o %T\\|%q\\|%C" | getline) {
      if($1~/RUNNING/){r[$2]+=$3} if($1~/PENDING/){p[$2]+=$3}
    }
  }
  {printf "%-12s%8i %12s %-6i %10i %5i/%-5i\n",$2,$1,$3,$5,$4,r[$2],p[$2]}'
}

function userqos {
    eval "$cmd_qos_u $1 '$fmt_a_user'" | awk 'BEGIN{FS="|";} {
    printf "%14s %-9s %-s\n", $1,$2,$14}'
}

function rescount {
    echo "Partition    Cores   Memory   AvgSize"
    eval "$cmd_queue_job '%P %C %D %m' -h -t $1" | awk '{c[$1]+=$2; m[$1]+=($4~/K/)?$2*$4*1000:$2*$4}
  END{for(p in c){printf "%-10s %7i %7.0fG %8iM\n",p,c[p],m[p]/1024,m[p]/c[p]}}'
}


commands "$@"

if [ "$watch" ]; then
    if [ "$header" ]; then
	#cmd="$cmd_parts '$fmt_s_parts'; echo; $cmd"
	cmd="$0 qos; echo; $cmd"
    fi
    $cmd_watch "$cmd"
else
    eval $cmd
fi
