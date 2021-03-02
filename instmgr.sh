#!/bin/bash
#------------------------------------------------
#
# startup container database and then start
# pluggable database
#
# instances that are not multitenant
# will startup without attempting
# to alter a PDB
#------------------------------------------------

export  timestamp=`date +%Y-%m-%d_%H-%M-%S`
export  log_file=${LOGDIR}/instmgr_${timestamp}_.log
exec > >(tee -a "$log_file") 2>&1

ARGUMENT_LIST=(
    "instance"
    "method"
)

# read arguments
opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        --instance)
            instance=$2
            shift 2
            ;;

        --method)
            method=$2
            shift 2
            ;;

        *)
            break
            ;;
    esac
done

function startup () 
{

#------------------------------------------------
# start instance
#------------------------------------------------

export ORACLE_SID=$instance
sqlplus -s /nolog <<EOF
column pdb_name format a15
column status   format a10
--
connect / as sysdba;
startup;
EOF

#------------------------------------------------
# check is database is PDB or CDB
#------------------------------------------------

_table="v\$database"
_is_container=`sqlplus -s /nolog <<EOF
set heading off
set feed off
--
connect / as sysdba;
SELECT  CDB FROM $_table;
EOF
`
_is_container=$(echo $_is_container | sed -e 's/\r//g')

#------------------------------------------------
# if its a container database start pluggable 
# databases
#------------------------------------------------

if [[ "$_is_container" == "YES" ]] 
then

_table="PDB\$SEED"
_pdbs=`sqlplus -s /nolog <<EOF
set heading off
column pdb_name format a15
--
connect / as sysdba;
SELECT pdb_name FROM dba_pdbs where pdb_name not in ('$_table');
EOF
`

for pdb in `echo ${_pdbs}`
do


sqlplus -s /nolog <<EOF
column pdb_name format a15
column status   format a10
--
connect / as sysdba;
alter session set container = ${pdb};
ALTER PLUGGABLE DATABASE ${pdb} OPEN READ WRITE;
SELECT pdb_name,status FROM dba_pdbs ORDER BY pdb_name;
EOF

done

fi

}

function shutdown ()
{

#------------------------------------------------
# shutdown instance
#------------------------------------------------

export ORACLE_SID=$instance
sqlplus -s /nolog <<EOF
column pdb_name format a15
column status   format a10
--
connect / as sysdba;
shutdown immediate;
EOF


}

#------------------------------------------------
# if its a container database start pluggable 
# databases
#------------------------------------------------
if [[ "$method" == "startup" ]]
then
  startup
fi


if [[ "$method" == "shutdown" ]]
then
  shutdown
fi


if [[ "$method" == "restart" ]]
then
  shutdown
  startup
fi
