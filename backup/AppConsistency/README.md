Application-Consistent Backups for Kubernetes Using CvTasks

To implement application-consistent backups for Kubernetes, you can execute tasks before and after taking volume snapshots.

Contains set of YAMLs needed by Commvault Kubernetes Agent to take application-consistent backups.

Install Applicatin Consistency CRDs:
kubectl apply -k deploy/

Relevant examples can be found in examples directory.

More information on Application Consistent Backups for Kubernetes Application.
https://documentation.commvault.com/2023e/essential/158712_application_consistent_backups_for_kubernetes_using_cvtasks.html
