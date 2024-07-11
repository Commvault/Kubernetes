#!/bin/bash

# Global variables
mysql_cvtask_template="templates/mysql-cvtask.template"
mysql_cvtaskset_template="templates/mysql-cvtaskset.template"
postgres_cvtask_template="templates/postgres-cvtask.template"
postgres_cvtaskset_template="templates/postgres-cvtaskset.template"
keydb_cvtask_template="templates/keydb-cvtask.template"
keydb_cvtaskset_template="templates/keydb-cvtaskset.template"

helm_username=""
helm_password=""
helm_db_name=""
common_mysql_username=""
common_mysql_password=""

mysql_appname=""
mysql_containername=""
mysql_podname=""
mysql_podnamespace=""
mysql_username=""
mysql_password=""

keydb_username=""
keydb_password=""

postgres_db_host="localhost"
postgres_username=""
postgres_password=""
postgres_dbport=""
postgres_dbname=""

target_namespace=""
target_database=""
mysql=0
postgresql=0
keydb=0
db_all=0
mariadb=0

logfile="/tmp/discovery.log"
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
	
	  # Set flags to 1 for the chosen database types. There can be multiple choices.
		  for each in ${filtered_db[@]}; do
			  case "$each" in
				mysql)
				  mysql=1
				  shift
				  ;;
				mariadb)
 				  mariadb=1
				  shift
				  ;;
				postgresql)
				  postgresql=1
				  shift
				  ;;
				keydb)
				  keydb=1
				  shift
				  ;;
				all)
				  db_all=1
				  shift
				  ;;
				*) 
				  echo "Invalid database specified"
				  display_usage
				  echo "Exiting..."
				  exit 1
				  ;;
			  esac
		  done
}

#----------------------------------
# Display the usage of the script
#----------------------------------
display_usage() {
      echo -e "\n Syntax:"
      echo "  CVK8SDiscoverDB.sh --help						Display this help"
      echo "  CVK8SDiscoverDB.sh --namespace <namespace> --db <db name>		Provide comma separater namespaces and db names. Specify 'all' to discover all databases in all namespaces."    
      echo "  Supported databases : mysql, postgresql, keydb, mariadb "
      echo ""
      exit 1
}


#--------------------------------------------------------------
# Read the database credentials from the file dbcredentials.txt
#--------------------------------------------------------------

read_db_credentials() {
	file_path=./dbcredentials.txt
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
		echo "Name : $name"
		echo "value : $value"
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


fetch_credentials_from_secret() {
						db_type=$1
						
						echo -n "Enter the namespace of the secret (Press Enter for default: $pod_namespace):"
						read secret_namespace
						
						if [ -z $secret_namespace ]; then
							secret_namespace=$pod_namespace
						fi
						
						secrets=$(kubectl get secrets -n $secret_namespace | awk '{print $1}')
						
						if [[ -z $secrets || $secrets == "" ]]; then
							echo "No secrets found in the speficied namespace"
							echo "Exiting !"
							exit 1
						fi
						
						echo "Below are the secrets present in the provided namespace."
						echo "-----------------------------------------------------"
						#echo $secrets |  awk '{gsub(" ", "\n", $0); print}'
						echo $secrets | awk '{for (i=2; i<=NF; i++) print $i}'
						
						echo "--------------------------------------------------------"
						echo -n "From the above, enter the secret name to use for $1 credentials : "
						read secret_name
						
	
						# Check if the secret exists
						if kubectl get secret $secret_name -n $secret_namespace  &> /dev/null; then
							secret_data=$(kubectl get secret "$secret_name" -n "$secret_namespace" -o jsonpath="{.data}")
							# Extract keys and values into arrays
							keys=($(echo $secret_data | jq -r 'keys[]'))
							values=($(echo $secret_data | jq -r '.[]'))
							echo "The provided Secret has the following key-value pairs"
							echo "-----------------------------------------------------"
							set=0
							# Print keys and values
							for ((i=0; i<${#keys[@]}; i++)); do
								values[$i]=$(echo ${values[$i]} | base64 -d)
  								echo "Key: ${keys[$i]}, Value: ${values[$i]} "
							done
							
							echo "-------------------------------------------------------"
							echo -n "Type in the key name that represents the $db_type username from the provided secret. [Press Enter if its not present] : "
							read key_name

							username=$(kubectl get secret "$secret_name" -n "$secret_namespace" -o jsonpath="{.data.$key_name}" | base64 --decode)

							#echo "Username : $username"

							if [ -z $username ]; then
								echo -n "$1 username not found in secret. Type it manually : "
								read username
								
							fi

							echo -n "Type in the key name that represents the $db_type password from the provided secret. [Press Enter if not present] : "
							read key_name

							password=$(kubectl get secret "$secret_name" -n "$secret_namespace" -o jsonpath="{.data.$key_name}" | base64 --decode)	

							if [ -z $password ]; then
								echo -n "$db_type password not found in secret. Type it manually : "
								read password
							fi
							
						else
							echo "Specified secret [$secret_name] does not exist in the namespace [$secret_namespace]"
							echo "Exiting..."
							exit 1
						fi
						general_username=$username
						general_password=$password
						case "$db_type" in
							"mysql")
								mysql_username=$username
								mysql_password=$password
								;;
							"postgresql")
								postgres_username=$username
								postgres_password=$password
							;;	
							"keydb")
								keydb_username=$username
								keydb_password=$password
							;;
							"mariadb")
								mysql_username=$username
								mysql_password=$password
							;;

							*)
								echo "Error ! Invalid DB type : $db_type"
								echo "Exiting"
								exit 1
							;;
						esac
}


#------------------------------------------------------------------------
# Scan through the namespaces and filter the ones we are interested in,
# as specified in the CLI parameters.
#-----------------------------------------------------------------------
scan_namespaces() {
	#echo "Scanning namespaces.."
	# Get a list of all namespaces
	all_ns=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name")
	namespace_list=()
	
	IFS=$'\n'  # Reset IFS to newline character
	read -rd '' -a namespace_list <<< "$all_ns"

	if [ $filtered_ns == "all" ]; then	
		filtered_ns=(${namespace_list[@]})
	fi  
	read_db_credentials
	# Loop through each namespace and filter out the one that were chosen at the CLI parameter
	for namespace in "${namespace_list[@]}"; do
  		for ns in "${filtered_ns[@]}"; do
    		if [ "$namespace" == "$ns" ]; then
			echo "Scanning namespace : [$namespace]"
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
					#read_db_credentials
					if [ "$mysql" == "1" ]; then
						discover_mysql_in_pod $pod $namespace 
					fi
					
					if [ "$mariadb" == "1" ]; then
						discover_mariadb_in_pod $pod $namespace 
					fi
					
					if [ "$postgresql" == "1" ]; then
						discover_postgres_in_pod $pod $namespace 
					fi

					if [ "$keydb" == "1" ]; then
						discover_keydb_in_pod $pod $namespace 
					fi

					if [ "$db_all" == "1" ]; then
						discover_mysql_in_pod $pod $namespace 
						discover_postgres_in_pod $pod $namespace 
						discover_keydb_in_pod $pod $namespace 
						discover_mariadb_in_pod $pod $namespace 
						
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
		echo "----> MySQL found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mysql"
	elif kubectl exec -it "$pod" -n "$namespace" -- type mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----> MySQL found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mysql"
	elif kubectl exec -it "$pod" -n "$namespace" -- which mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----> MySQL found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mysql"
	else
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
	fi
}

discover_mariadb_in_pod() {
	pod=$1
	namespace=$2
	echo `date +"%Y-%m-%d %H:%M:%S"` "Discovering MySQL in pod $pod and namespace $namespace.." >> $logfile
	if kubectl exec -it "$pod" -n "$namespace" -- command -v mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----> MariaDB found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mariadb"
	elif kubectl exec -it "$pod" -n "$namespace" -- type mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----> MariaDBf ound in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mariadb"
	elif kubectl exec -it "$pod" -n "$namespace" -- which mysql > /dev/null 2>> $logfile ; then
		# If "mysql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----> MariaDB found in pod:[$pod] Namespace:[$namespace] Container:[$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "MySQL found in pod: $pod (Namespace: $namespace, Container: $container_name).." >> $logfile
		create_cvtask $namespace $pod $container_name "mariadb"
	else
		echo `date +"%Y-%m-%d %H:%M:%S"` "MariaDB not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
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
		# If "psql" command is found, determine namespace, container name, and pod name
		container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
		echo "----PostGreSQL found in pod: [$pod] Namespace: [$namespace] Container: [$container_name]"
		found=1
		echo `date +"%Y-%m-%d %H:%M:%S"` "PostGreSQL found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
		create_cvtask $namespace $pod $container_name "postgres"
	else
		echo `date +"%Y-%m-%d %H:%M:%S"` "PostGreSQL not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
	fi
}

#--------------------------------------------------
# Check for the existence of "keydb" inside the pod
#--------------------------------------------------
discover_keydb_in_pod()
{
  pod=$1
  namespace=$2
  echo `date +"%Y-%m-%d %H:%M:%S"` "Discovering KeyDB in pod $pod and namespace $namespace.." >> $logfile
   if kubectl exec -it "$pod" -n "$namespace" -- which keydb-cli &> /dev/null; then
        # If "keydb" command is found, determine namespace, container name, and pod name
        container_name=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
        echo "----> KeyDB found in pod: [$pod] Namespace: [$namespace] Container: [$container_name]"
        found=1
        echo `date +"%Y-%m-%d %H:%M:%S"` "KeyDB found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
        create_cvtask $namespace $pod $container_name "keydb"
   else
        echo `date +"%Y-%m-%d %H:%M:%S"` "KeyDB not found in pod: $pod (Namespace: $namespace, Container: $container_name)" >> $logfile
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
	instance_name=""
	
	# If the pod is a helm-based deployment, check the "app.kubernetes.io/instance=galeradb" and use that for the name of the CVTask.
	labels=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.metadata.labels}')
	is_helm=$(echo "$labels" | jq -r 'to_entries | map("\(.key)=\(.value)") | .[]' | while read each; do grep -i "app.kubernetes.io/managed-by" | cut -d '=' -f2 ; done)
	if [[ -n $is_helm && $is_helm == "Helm" ]]; then
		echo "[$pod_name] - is a helm chart object"
		helm_app=1
		instance_name=$(echo "$labels" | jq -r 'to_entries | map("\(.key)=\(.value)") | .[]' | grep -i "app.kubernetes.io/name" | cut -d '=' -f2 )
		echo $instance_name
		if [ -z $instance_name ]; then
			echo "No label "app.kubernetes.io/instance" found for this Helm object. Please add it and rerun"
			exit 1
		fi
	fi
	
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
		mysql|mariadb)
			if [[ $mysql_username == "" || $mysql_password == "" ]]; then
				read_username_password $db
			else
				echo -n "Use the same credentials ? [Username : $mysql_username  Password : $mysql_password] (Press enter for default [yes]/no) : "
				read choice
				if [[ $choice == "yes" || -z $choice || $choice == "" ]]; then
					echo "Using the same credentials:"
					# skip reading the credentials again
				else
					read_username_password $db
				fi
			fi
			# For MySQL db, use the mysql yaml template
			cvtask_filename="cvtask-"$namespace"-"$pod".yaml"
			cvtaskset_filename="cvtaskset-"$namespace"-"$pod".yaml"
			
			echo `date +"%Y-%m-%d %H:%M:%S"` "Pod : $pod_name" >> $logfile
			
			# Create a clone of cvtask and cvtaskset yamls from the template and replace the appropriate feilds.
			if [ -f $mysql_cvtask_template ] && [ -f $mysql_cvtaskset_template ]; then
				echo "Creating custom resource yamls for quiescing $db."
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $mysql_cvtask_template to $cvtask_filename" >> $logfile
				cp "$mysql_cvtask_template" "$cvtask_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $mysql_cvtaskset_template to $cvtaskset_filename" >> $logfile
				cp "$mysql_cvtaskset_template" "$cvtaskset_filename"
				
				# If this is a Helm application, then the CVTask name should be the instance name of the helm app.
				#if [[ -n $is_helm && $is_helm == "Helm" ]]; then
				if [[ -n "${is_helm-}" && "$is_helm" == "Helm" ]]; then
					pod_name=$instance_name
				fi 
				
				# Replace the placeholder in the yamls with appropriate values
				
				echo `date +"%Y-%m-%d %H:%M:%S"` "Replacing values in yaml..." >> $logfile
				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"

				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
				sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"

				sed -i "s/"mysql_username"/$mysql_username/g" "$cvtask_filename"
				sed -i "s/"mysql_password"/$mysql_password/g" "$cvtask_filename"

				sed -i "s/"my-pod_placeholder"/$app_name/g" "$cvtaskset_filename"
				sed -i "s/"prepost_placeholder"/$pod_namespace/g" "$cvtaskset_filename"

			else
				echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! $db template files for cvtask and cvtaskset not found." >> $logfile
				echo "Error ! $db template files for cvtask and cvtaskset not found !"
				echo "Exiting..."
				exit 1
			fi
		;;

		postgres)
			# Ensure we have postgressql details before we create the cvtask yamls
			if [[ $postgres_username == "" || $postgres_password == "" ]]; then
				read_username_password $db
			
			else
				echo -n "Use the same credentials ? [Username : $postgres_username  Password : $postgres_password ]  (Press enter for default [yes]/no) : "
				read choice
				echo "Choice : $choice"
				if [[ $choice == 'yes' || -z $choice || $choice == "" ]]; then
					echo "Using the same credentials:"
					# skip reading the credentials again
				else
					read_username_password $db
				fi
			fi
			
			# For postgres db, create the yaml file naming format using namespace and pod name 
			cvtask_filename="cvtask-"$namespace"-"$pod".yaml"
			cvtaskset_filename="cvtaskset-"$namespace"-"$pod".yaml"
	
			# Create a clone of cvtask and cvtaskset yamls from the template
			if [ -f $postgres_cvtask_template ] && [ -f $postgres_cvtaskset_template ]; then
				echo "Creating custom resource yamls for quiescing PostGreSQL.."
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $postgres_cvtask_template to $cvtask_filename" >> $logfile
				cp "$postgres_cvtask_template" "$cvtask_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $postgres_cvtaskset_template to $cvtask_filename" >> $logfile
				cp "$postgres_cvtaskset_template" "$cvtaskset_filename"
				
				echo `date +"%Y-%m-%d %H:%M:%S"` "Replacing values in the postgres yaml" >> $logfile
				
				# If this is a Helm application, then the CVTask name should be the instance name of the helm app.
				if [[ -n $is_helm && $is_helm == 'Helm' ]]; then
					pod_name=$instance_name
				fi 

				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
				sed -i "s/"postgres_username_placeholder"/$postgres_username/g" "$cvtask_filename"
				sed -i "s/"postgres_db_name_placeholder"/$postgres_db_name/g" "$cvtask_filename"

				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
				sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"

				sed -i "s/"my-pod_placeholder"/$app_name/g" "$cvtaskset_filename"
				sed -i "s/"prepost_placeholder"/$pod_namespace/g" "$cvtaskset_filename"
				
			else
				echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! PostGreSQL template files for cvtask and cvtaskset not found." >> $logfile
				echo "Error ! PostgresSQL template files for cvtask and cvtaskset not found !"
				echo "Exiting..."
				exit 1
			fi
		;;
		
		keydb)
				echo "Username : $keydb_username"
				echo "Password : $keydb_password"
				if [[ $keydb_username == "" || $keydb_password == "" || -z $keydb_username || -z $keydb_password ]]; then
					read_username_password $db
				else
					echo -n "Use the same credentials ? [Username : $keydb_username  Password : $keydb_password]  (Press enter for default [yes]/no) : "
					read choice
					if [[ $choice == 'yes' || -z $choice || $choice == "" ]]; then
						# skip reading the credentials again
						echo "Using the same credentials:"
					else
						read_username_password $db
					fi
				fi

			# For keydb, use the keydb yaml template
			cvtask_filename="cvtask-"$namespace"-"$pod".yaml"
			cvtaskset_filename="cvtaskset-"$namespace"-"$pod".yaml"
			
			echo `date +"%Y-%m-%d %H:%M:%S"` "Pod : $pod_name" >> $logfile
			
			# Create a clone of cvtask and cvtaskset yamls from the template and replace the appropriate feilds.
			if [ -f $keydb_cvtask_template ] && [ -f $keydb_cvtaskset_template ]; then
				echo "Creating custom resource yamls for quiescing KeyDB.."
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $keydb_cvtask_template to $cvtask_filename" >> $logfile
				cp "$keydb_cvtask_template" "$cvtask_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Copying $keydb_cvtaskset_template to $cvtaskset_filename" >> $logfile
				cp "$keydb_cvtaskset_template" "$cvtaskset_filename"
				echo `date +"%Y-%m-%d %H:%M:%S"` "Replacing values in yaml..." >> $logfile
				
				# If this is a Helm application, then the CVTask name should be the instance name of the helm app.
				if [[ -n $is_helm && $is_helm == "Helm" ]]; then
					pod_name=$instance_name
				fi 
				
				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtask_filename"
				sed -i "s/"keydb_password"/$keydb_password/g" "$cvtask_filename"
				
				sed -i "s/"cvtaskname_placeholder"/"cvtask"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
				sed -i "s/"cvtasksetname_placeholder"/"cvtaskset"-$pod_namespace"-"$pod_name"/g "$cvtaskset_filename"
				sed -i "s/"my-pod_placeholder"/$app_name/g" "$cvtaskset_filename"
				sed -i "s/"prepost_placeholder"/$pod_namespace/g" "$cvtaskset_filename"
			else
				echo `date +"%Y-%m-%d %H:%M:%S"` "Error ! keydb template files for cvtask and cvtaskset not found." >> $logfile
				echo "Error ! keydb template files for cvtask and cvtaskset not found !"
				echo "Exiting..."
				exit 1
			fi
		;;
	esac
	echo "-------------------------------------------------------------------------------------"
}


read_username_password()
{
	db_choice=$1
	echo "Choose the correct option to fetch the $db_choice credentials :"
	echo "---------------------------------------------"
	echo "[1] Specify k8s secret name as $db_choice password"
	echo "[2] Specify password as plain text"
	echo "[*] Exit script"
	echo "---------------------------------------------"
	echo -n "Enter Choice: "
	read choice

	if [ "$choice" = "1" ]; then
		fetch_credentials_from_secret $db_choice
	elif [ "$choice" = "2" ]; then
		echo -n "Enter the username for $db_choice database running inside the  pod : [$pod_name] in namespace [$pod_namespace] : "
		read  general_username
		echo -n "Enter the passoword for $db_choice database running inside the  pod : [$pod_name] in namespace [$pod_namespace] : "
		read  general_password
	else 
		echo "Please re-run the script and specify a correct $db_choice password"
		echo "Exiting !"
		exit 1
	fi
			
	case "$db_choice" in
							"mysql")
								mysql_username=$general_username
								mysql_password=$general_password
								;;
							"mariadb")
								mysql_username=$general_username
								mysql_password=$general_password
								;;
							"keydb")
								keydb_username=$general_username
								keydb_password=$general_password
							;;
							"postgres")
								postgres_username=$general_username
								postgres_password=$general_password
								echo -n "Enter the DB name for $db_choice running inside pod : [$pod_name] in namespace : [$pod_namespace] : "
								read postgres_db_name
							;;

							*)
								echo "Error ! Invalid DB type : $db_type"
								echo "Exiting"
								exit 1
							;;
	esac

}



apply_yamls ()
{
  cd manifests
  result=""
  output=""
  ls | while IFS= read -r each; do
	if [[ $each == *.yaml ]]; then
		echo `date +"%Y-%m-%d %H:%M:%S"` "Applying the yamls...." >> $logfile
		#kubectl create -f $each >> $logfile 2 >> "$result"
		
		tempfile=$(mktemp)
		result=$(kubectl create -f $each 2>$tempfile)
		output=$(<"$tempfile")
		
		echo $output
		echo $result >> $logfile
	fi

	if [[ $output == *Error* ]]; then
		if [[ $output == *AlreadyExists* ]]; then
			name="${each%%.*}"
			echo -e "Custom Resource [$each] already exists ! you can delete is manually by running the command [kubectl delete cvtask $name -n cv-config]"
		fi
		echo -e "Error applying custom resource yaml [$each]."
	else 
		echo -e "Successfully applied yaml [$each]"
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
	# Move all the yamls that are ready to apply, to the 'manifests' folder
	file_list=$(find . -type f -name "*.yaml")
	for each in $file_list; do
		#echo $each
		mv $each manifests/
	done

	echo "------------------------------------------------------------"
	echo "Custom Resource yamls are created inside the folder 'manifests'" 
	echo -n "Do you want to apply all the generated Custom Resource yamls to the kubernetes cluster (default[yes]/no) ? "
	read response
	if [[ "$response" == "yes" || $response == ""  ]]; then
		echo -e "Applying CVTask and CVTaskSet yamls to the cluster..."
		apply_yamls
	else
		echo "Manually apply the yamls created under the 'manifests' folder"
	fi
	echo `date +"%Y-%m-%d %H:%M:%S"` "Exiting.." >> $logfile
else
	echo "No databases found in the specified namespace(s)"
fi
echo "Exiting..."
