kind: DaemonSet
metadata:
  name: logging-test-daemonset
spec:
  selector:
    matchLabels:
      name: logging-test
  template:
    metadata:
      labels:
        name: logging-test 
    spec:
      containers:
      - env:
        - name: LOG_INTERVAL 
          value: "5"
        image: docker-registry.default.svc:5000/mylogging/logging-check-daemonset:0.1
        imagePullPolicy: IfNotPresent
        name: logging-test 
      nodeSelector:
        logging-infra-fluentd: "true"
      restartPolicy: Always
      securityContext: {}
      terminationGracePeriodSeconds: 30
