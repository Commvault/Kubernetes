#!/bin/bash

# Global variables
mysql_cvtask_template="templates/mysql-cvtask.template"
mysql_cvtaskset_template="templates/mysql-cvtaskset.template"
postgres_cvtask_template="templates/postgres-cvtask.template"
postgres_cvtaskset_template="templates/postgres-cvtaskset.template"

mysql_appname=""
mysql_containername=""
mysql_podname=""
mysql_podnamespace=""
mysql_username="test"
mysql_password="test"

postgres_db_host="localhost"
postgres_username="xxx"
postgres_password="xxx"
postgres_dbport="xxx"
postgres_dbname="xxx"

target_namespace=""
target_database=""
mysql=0
postgresql=0
db_all=0

logfile="discovery.log"
found=0

#--------------------------------------------------------
# Parse the CLI Parameters
# Syntax : ./discover.sh --namespace <name> --db <dbtype>
# Values can be comman seperated
#--------------------------------------------------------
parse_cli_params() {
	if [ $# != 4 ]; then
	 echo -e "\n Insufficient parameters..."
	 display_usage
	 exit
	fi

	while [[ $# -gt 0 ]]; do
	  case "$1" in
		--namespace)
		  target_namespace="$2"
		  echo `date +"%Y-%m-%d %H:%M:%S"` "Namespaces chosen : $target_namespace" >> $logfile
		  IFS=","
		  read -ra filtered_ns <<< "$target_namespace"
		  shift
		  ;;
		--db)
		  target_database="$2"
		  echo `date +"%Y-%m-%d %H:%M:%S"` "Databases chosen: $target_database" >> $logfile
		  IFS=","
		  read -ra filtered_db <<< "$target_database"
		  
		  # Set flags to 1 for the chosen database types. There can be multiple choices.
		  for each in ${filtered_db[@]}; do
			  case "$each" in
				mysql)
				  mysql=1
				  shift
				  ;;
				postgresql)
				  postgresql=1
				  shift
				  ;;
				all)
				  db_all=1
				  shift
				  ;;
				*) 
				  echo "Invalid database specified. Choices [mysql/postgresql/all]"
				  echo "Exiting..."
				  exit 1
				  ;;
			  esac
		  done
		  shift
		  ;;
		--help)
		 display_usage
		 ;;
		*)
		  echo "Invalid argument: $1"
		  display_usage
		  exit 1
		  ;;
	  esac
	  shift
	done
}

#----------------------------------
# Display the usage of the script
#----------------------------------
display_usage() {
      echo -e "\n Syntax:"
      echo "  discover --help						Display this help"
      echo "  discover --namespace <namespace> --db <db name>		Provide comma separater namespaces and db names. Specify 'all' to discover all databases in all namespaces."    
      echo ""
      exit 1
}


#--------------------------------------------------------------
# Read the database credentials from the file dbcredentials.txt
#--------------------------------------------------------------

read_db_credentials() {
	file_path=./dbcredentials.txt
        mysql_username=""
        mysql_password=""
        postgres_username=""
        postgres_password=""
        postgres_db_name=""
	# Check if the credentials file exists
	if [ ! -f "$file_path" ]; then
		echo "File not found: $file_path"
		exit 1
	fi

	# Read the username and password from the mysql file
	while IFS= read -r line; do
		# Check if the line is empty or starts with a comment character "#"
		if [[ -z "$line" || "$line" == \#* ]]; then
			continue
		fi

		name="${line%%=*}"
		value="${line#*=}"

		case "$name" in
			"mysql_username")
				mysql_username=$value
				;;
			"mysql_password")
				mysql_password=$value
				;;
			"postgres_username")
				postgres_username=$value
				;;
			"postgres_password")
				postgres_password=$value
				;;
			"postgres_db_name")
				postgres_db_name=$value
				;;
			*)
				echo "Error ! Invalid value in dbcredentials.txt : $name"
				echo "Exiting"
				exit 1
      ;;
  esac
done < "$file_path"
}


#------------------------------------------------------------------------
# Scan through the namespaces and filter the ones we are interested in,
# as specified in the CLI parameters.
#-----------------------------------------------------------------------
scan_namespaces() {
	echo "Scanning namespaces..."
	# Get a list of all namespaces
	all_ns=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name")
	namespace_list=()
	
	IFS=$'\n'  # Reset IFS to newline character
	read -rd '' -a namespace_list <<< "$all_ns"

	if [ $filtered_ns == "all" ]; then	
		filtered_ns=(${namespace_list[@]})
	fi  

	# Loop through each namespace and filter out the one that were chosen at the CLI parameter
	for namespace in "${namespace_list[@]}"; do
  		for ns in "${filtered_ns[@]}"; do
    		if [ "$namespace" == "$ns" ]; then
      			echo `date +"%Y-%m-%d %H:%M:%S"` "Probing pods in the namespace $namespace" >> $logfile

  				# List all the pods in the current namespace
  				pod_list=$(kubectl get pods -n "$namespace" --no-headers -o custom-columns=":metadata.name")
				if [ "$pod_list" == "*error*" ]; then
					echo "Failed to get list of pods from namespace : $namespace"
					echo "Exiting..."
					exit 1
				fi

  				# Probe the pods for the dataabases chosen at the CLI parameter.
  				for pod in $pod_list; do
					read_db_credentials
					if [ "$mysql" == "1" ]; then
						discover_mysql_in_pod $pod $namespace
					fi
					
                    			if [ "$postgresql" == "1" ]; then
						discover_postgres_in_pod $pod $namespace
					fi
					
                   			 if [ "$db_all" == "1" ]; then
						discover_mysql_in_pod $pod $namespace
						discover_postgres_in_pod $pod $namespace
					fi
  				done
    		fi
  		done
	done
}


#-----------------------------------------------------------
# Check for the existence of "mysql" db inside the pod
#-----------------------------------------------------------
discover_mysql_in_pod() {
	pod=$1
	namespace=$2
	echo `date +"%Y-%m-%d %H:%M:%S"` "Discovering MySQL in pod $pod and namespace $namespace.." >> $logfile
        if kubectl exec -it "$pod" -n "$namespace" -- command -v mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
        	container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
        	echo "----MySQL found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
        	create_cvtask $namespace $pod $container_name "mysql"
	else
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
	fi
}
 
 
#-----------------------------------------------------------
# Check for the existence of "Postgres" db inside the pod
#-----------------------------------------------------------
discover_postgres_in_pod()
{
   pod=$1
   namespace=$2
   echo `date +"%Y-%m-%d %H:%M:%S"` "Discovering PostGreSQL in pod $pod and namespace $namespace.." >> $logfile
   if kubectl exec -it "$pod" -n "$namespace" -- which psql &> /dev/null; then
	# If "mysql" command is found, determine namespace, container name, and pod name
        container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
        echo "----PostGreSQL found in pod: [$pod] Namespace: [$namespace] Container: [$container_name]"
	found=1
	echo `date +"%Y-%m-%d %H:%M:%S"` "PostGreSQL found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
        create_cvtask $namespace $pod $container_name "postgres"
   else
	echo `date +"%Y-%m-%d %H:%M:%S"` "PostGreSQL not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
   fi

}

create_cvtask() {
	pod_namespace=$1
	pod_name=$2
	app_name=$3
	container_name=$3
	db=$4
	cvtask_filename=""
	cvtaskset_filename=""
	
	echo `date +"%Y-%m-%d %H:%M:%S"` "Creating cvtask objects" >> $logfile
	 
	if [[ -z $app_name || -z $pod_namespace || -z $container_name || -z  $pod_name ]] ; then
		echo `date +"%Y-%m-%d %H:%M:%S"` "AppName: $app_name" >> $logfile
		echo `date +"%Y-%m-%d %H:%M:%S"` "Pod : $pod_name" >> $logfile
		echo `date +"%Y-%m-%d %H:%M:%S"` "Namespace : $pod_namespace" >> $logfile
		echo `date +"%Y-%m-%d %H:%M:%S"` "Container : $container_name" >> $logfile
		echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! Not all parameters identified...Exiting !" >> $logfile
		echo "Error ! Not all parameters identified from discovery...Please check discovery.log for details."
		echo "Exiting !"
		exit 1
	fi
	
	case "$db" in
		mysql)
			# Ensure we have mysql username and password
			if [[ -z $mysql_username || -z $mysql_password ]]; then
				echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL credentials not spcified in the dbcredentials.txt file. Attemptig to read from console." >> $logfile
				echo "MySQL username and password not specified in the dbcredentials.txt file"
				echo -n "Do you want to specify it now at runtime (yes/no) ? "
				read response
				
				if [ "$response" = "yes" ]; then
					echo -n "Enter the username for mysql running inside the  pod : [$pod_name] in namespace [$pod_namespace] : "
					read mysql_username
					echo -n "Enter the password for mysql user [$mysql_username] for pod : [$pod_name] in namespace : [$pod_namespace] : "
					read mysql_password
				else
					echo "Please update the dbcredentials.txt file and rerun this script."
					echo "Exiting..."
					exit 1
				fi
			fi
			
			# For MySQL db, use the mysql yaml template
			cvtask_filename="cvtask-"$namespace"-"$pod".yaml"
			cvtaskset_filename="cvtaskset-"$namespace"-"$pod".yaml"
			
			echo `date +"%Y-%m-%d %H:%M:%S"` "Pod : $pod_name" >> $logfile
			
			# Create a clone of cvtask and cvtaskset yamls from the template and replace the appropriate feilds.
			if [ -f $mysql_cvtask_template ] && [ -f $mysql_cvtaskset_template ]; then
				echo "    Creating custom resource yamls for quiescing MySQL.."
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $mysql_cvtask_template to $cvtask_filename" >> $logfile
				cp "$mysql_cvtask_template" "$cvtask_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $mysql_cvtaskset_template to $cvtaskset_filename" >> $logfile
				cp "$mysql_cvtaskset_template" "$cvtaskset_filename"

				echo `date +"%Y-%m-%d %H:%M:%S"` "Replacing values in yaml..." >> $logfile
				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"

                                sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
                                sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"

                                sed -i "s/"mysql_username"/$mysql_username/g" "$cvtask_filename"
                                sed -i "s/"mysql_password"/$mysql_password/g" "$cvtask_filename"

                                sed -i "s/"my-pod_placeholder"/$app_name/g" "$cvtaskset_filename"
                                sed -i "s/"prepost_placeholder"/$pod_namespace/g" "$cvtaskset_filename"




			#	sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
                	#	sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
			#	sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
			#	sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
#
#				sed -i "s/"cv-task"/cv-config/g" "$cvtaskset_filename"
#				sed -i "s/"mysql_username"/$mysql_username/g" "$cvtask_filename"
#				sed -i "s/"mysql_password"/$mysql_password/g" "$cvtask_filename"
#				sed -i "s/"app-db"/$app_name/g" "$cvtask_filename"
#				sed -i "s/"prod-db"/$pod_namespace/g" "$cvtask_filename"
#				sed -i "s/"app-server"/$container_name/g" "$cvtask_filename"
#				sed -i "s/"custom-app"/$pod_name/g" "$cvtask_filename"
#				sed -i "s/"my-pod"/$app_name/g" "$cvtaskset_filename"
#				sed -i "s/"prepost"/$pod_namespace/g" "$cvtaskset_filename"
			else
				echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! MySQL template files for cvtask and cvtaskset not found." >> $logfile
				echo "Error ! MySQL template files for cvtask and cvtaskset not found !"
				echo "Exiting..."
				exit 1
			fi
		;;

		postgres)
			# Ensure we have postgressql details before we create the cvtask yamls
			if [[ -z $postgres_username || -z $postgres_password || -z $postgres_db_name ]] ; then
				echo `date +"%Y-%m-%d %H:%M:%S"` "PostGreSQL credentials not spcified in the dbcredentials.txt file. Attemptig to read from console." >> $logfile
				echo "PostGreSQL details not specified in the dbcredentials.txt file"
				echo -n "Do you want to specify it now at runtime (yes/no) ? "
				read response
					
				if [ "$response" == "yes" ]; then
					echo -n "Enter the username for postgresql running inside the pod : [$pod_name] in namespace [$pod_namespace] : "
					read postgres_username
					#echo -n "Enter the password for postgresql user [$postgres_username] for pod : [$pod_name] in namespace : [$pod_namespace] : "
					#read postgres_password
					echo -n "Enter the db name for postgresql running inside the pod : [$pod_name] in namespace : [$pod_namespace] : "
					read postgres_db_name
				else
					echo "Please update the dbcredentials.txt file and rerun this script."
					echo "Exiting..."
					exit 1
				fi
			fi
			
			# For postgres db, create the yaml file naming format using namespace and pod name 
			cvtask_filename="cvtask-"$namespace"-"$pod".yaml"
			cvtaskset_filename="cvtaskset-"$namespace"-"$pod".yaml"
	
			# Create a clone of cvtask and cvtaskset yamls from the template
			if [ -f $postgres_cvtask_template ] && [ -f $postgres_cvtaskset_template ]; then
				echo "    Creating custom resource yamls for quiescing PostGreSQL.."
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $postgres_cvtask_template to $cvtask_filename" >> $logfile
				cp "$postgres_cvtask_template" "$cvtask_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $postgres_cvtaskset_template to $cvtask_filename" >> $logfile
				cp "$postgres_cvtaskset_template" "$cvtaskset_filename"
				
				echo `date +"%Y-%m-%d %H:%M:%S"` "Replacing values in the postgres yaml" >> $logfile

				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
				sed -i "s/"postgres_username_placeholder"/$postgres_username/g" "$cvtask_filename"
				sed -i "s/"postgres_db_name_placeholder"/$postgres_db_name/g" "$cvtask_filename"
   
                                sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
                                sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"

                                sed -i "s/"my-pod_placeholder"/$app_name/g" "$cvtaskset_filename"
                                sed -i "s/"prepost_placeholder"/$pod_namespace/g" "$cvtaskset_filename"








			#	sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
			#	sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
#
#				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
#				sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
#
#				sed -i "s/"cv-task"/cv-config/g" "$cvtaskset_filename"
#
#				sed -i "s/"app-db"/$app_name/g" "$cvtask_filename"
#				sed -i "s/"prod-db"/$pod_namespace/g" "$cvtask_filename"
#				sed -i "s/"app-server"/$container_name/g" "$cvtask_filename"
#				sed -i "s/"custom-app"/$pod_name/g" "$cvtask_filename"
#				
#				sed -i "s/"my-pod"/$app_name/g" "$cvtaskset_filename"
#				sed -i "s/"prepost"/$pod_namespace/g" "$cvtaskset_filename"
#				sed -i "s/"cv-task"/cv-config/g" "$cvtaskset_filename"
				
			else
				echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! PostGreSQL template files for cvtask and cvtaskset not found." >> $logfile
				echo "Error ! PostgresSQL template files for cvtask and cvtaskset not found !"
				echo "Exiting..."
				exit 1
			fi
		;;
	esac
}

apply_yamls ()
{
  cd manifests
  ls | while read each; do
    if [[ $each == *.yaml ]]; then
       echo `date +"%Y-%m-%d %H:%M:%S"` "Applying the yamls...." >> $logfile
       kubectl create -f $each >> $logfile
       exit_code=$?
       if [ $exit_code -ne 0 ]; then
		echo "Error ! Custom Resource : [$each] failed to be applied..."
       fi
    fi
  done
  cd ..
}


if command -v "kubectl" &> /dev/null; then
  echo "Starting script.."
else
  echo "kubectl command does not exist. Please install it.."
  echo "Exiting.."
  exit 0
fi


mkdir -p manifests
rm -f manifests/*.yaml

echo `date +"%Y-%m-%d %H:%M:%S"` "Starting...." >> $logfile
parse_cli_params "$@"
scan_namespaces

if [ $found == 1 ]; then
	# Move all the yamls that are ready to apply, to a seperate folder
	file_list=$(find . -type f -name "*.yaml")
	for each in $file_list; do
  		echo $each
  		mv $each manifests/
	done

	echo "------------------------------------------------------------"
	echo "Custom Resource yamls are created inside the folder 'manifests'" 
	echo -n "Do you want to apply all the generated Custom Resource yamls to the kubernetes cluster (yes/no) ? "
	read response
	if [ "$response" == "yes" ]; then
		apply_yamls
	fi
	echo `date +"%Y-%m-%d %H:%M:%S"` "Exiting.." >> $logfile
else
	echo "No databases found in the specified namespace(s)"
fi
echo "Exiting..."
