#!/bin/bash

# The original source of this script is from 
# https://bugs.launchpad.net/openstack-ci/+bug/979227
# Authored by Drragh Bailey (dbailey)-k

function cleanup() {
    revert
}


function get_config_data() {
    local config_path=$1
    local config="$1/etc/gerrit.config"
    local secure="$1/etc/secure.config"

    [[ ! -e "${config}" ]] && { echo "No gerrit config file supplied!"; exit 2; }
    [[ ! -e "${secure}" ]] && { echo "No gerrit secure file supplied!"; exit 2; }


    CONFIG=${config}
    DB_HOST=$(git config --file ${config} --get database.hostname)
    DB_NAME=$(git config --file ${config} --get database.database)
    DB_USER=$(git config --file ${config} --get database.username)
    DB_PASSWD=$(git config --file ${secure} --get database.password)
}

function update_gerrit_config() {
    if [[ -z "${DB_HOST}" ]] || [[ -z "${DB_NAME}" ]]
    then
	echo "Cannot build recognizable url, exiting"
	exit 2
    fi

    echo "Setting database.url"
    git config --file ${CONFIG} database.url 
jdbc:mysql://${DB_HOST}/${DB_NAME}?useUnicode=yes\&characterEncoding=UTF-8\&sessionVariables=storage_engine=InnoDB 
||
	{ echo "Problem setting the database url configuration setting"; exit 1; 
}

}

function reset_gerrit_config() {
    echo "Removing database.url"
    git config --file ${CONFIG} --unset database.url
}

function backup_gerrit_db() {
    
    echo "Backing up db ${DB_NAME}"
    mysqldump -h ${DB_HOST} -u ${DB_USER} ${DB_PASSWD:+-p${DB_PASSWD}} --skip-opt 
--add-drop-table \
            --add-locks --create-options --disable-keys --lock-tables --quick 
--quote-names \
            --skip-set-charset --default-character-set=latin1 ${DB_NAME} > 
${DB_NAME}-backup.sql
}

function convert_gerrit_db() {
    
    echo "Converting db sql backup ${DB_NAME}-backup.sql to utf8 in 
${DB_NAME}-utf8.sql"
    cat ${DB_NAME}-backup.sql | sed -e 's:latin1:utf8:g' -e 's:MyISAM:InnoDB:g' > 
${DB_NAME}-utf8.sql
    
}

function restore_db() {

    echo "Restoring previous backup of DB"
    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_PASSWD:+-p${DB_PASSWD}} 
--default-character-set=utf8 \
	${DB_NAME} -e "ALTER DATABASE ${DB_NAME} CHARACTER SET latin1 COLLATE 
latin1_swedish_ci;"

    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_PASSWD:+-p${DB_PASSWD}} ${DB_NAME} < 
${DB_NAME}-backup.sql 
}

function load_converted_db() {


    echo "Loading convert DB sql"
    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_PASSWD:+-p${DB_PASSWD}} 
--default-character-set=utf8 \
	${DB_NAME} -e "ALTER DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE 
utf8_general_ci;" ||
	{ echo "Problem converting the database character set"; exit 1; }

    # this caught me by surpise, but generally the console redirection results in 
the
    # characters being read in with latin1 encoding. May be dependent on system 
locale
    # settings.
    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_PASSWD:+-p${DB_PASSWD}} 
--default-character-set=latin1 \
	${DB_NAME} < ${DB_NAME}-utf8.sql
}

function convert() {
    backup_gerrit_db
    convert_gerrit_db

    trap cleanup "EXIT" "SIGTRAP" "SIGKILL" "SIGTERM"
    update_gerrit_config
    load_converted_db
    trap - "EXIT" "SIGTRAP" "SIGKILL" "SIGTERM"
}

function revert() {
    reset_gerrit_config
    restore_db
}

USAGE="$0 ACTION [path]

  ACTION   convert, revert or backup
  path     path to gerrit directory
"

if [ $# -ne 2 ]
then
    echo "${USAGE}"
    exit 2
fi

get_config_data $2

case $1 in
    "backup")
        backup_gerrit_db
        ;;
    "convert")
	convert
	;;
    "revert")
	revert
	;;
    *)
	echo "Invalid action"
	echo "${USAGE}"
	exit 2
esac
