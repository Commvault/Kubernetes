apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: cvtasks.k8s.cv.io
spec:
  group: k8s.cv.io
  names:
    kind: CvTask
    listKind: CvTaskList
    plural: cvtasks
    singular: cvtask
    shortNames:
    - cvtask
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        description: CvTask is the Schema for the cvtasks API for pre post scripts running.
        properties:
          apiVersion:
            type: string
          kind:
            type: string
          metadata:
            type: object
          spec:
            properties:
              prebackupsnapshot:
                properties:
                  cmdtype:
                    type: string
                    enum:
                    - command
                    - scripttext
                    - localscript
                  command:
                    type: string
                  args:
                    type: array
                    items:
                      type: string
                type: object
              postbackupsnapshot:
                properties:
                  cmdtype:
                    type: string
                    enum:
                    - command
                    - scripttext
                    - localscript
                  command:
                    type: string
                  args:
                    type: array
                    items:
                      type: string
                type: object
            type: object
        required:
        - spec
