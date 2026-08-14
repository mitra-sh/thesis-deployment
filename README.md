This project contains the deployment and network-simulation setup used to run the experiments.

It builds a simulated network across the Docker Swarm nodes hosting the Storm pipeline, using Linux traffic control (tc/netem) to apply configurable latency and bandwidth thresholds between nodes, based on values defined in latencyFile.csv and edgeDeviceBandwidthInfo.csv.

It also includes scripts to extract logs from each node's Storm supervisor containers after a run, for later analysis.

To run a topology on the cluster:

- docker exec -it $(docker ps -q --filter "name=nimbus") /bin/bash -c "cd /bin && storm jar /apache-storm-2.7.0/ShuffleTesting-2.7.0-exclude-storm.jar streamProcessor.topology.Topology topology && exit"

The above example corresponds to one specific scenario. For every scenario, the topology class (and sometimes the packaged jar itself) needs to be changed to match the experiment being run.

On the same master node, the orchestrator is started with:
- java -jar LoadBalancerDemo-0.0.1-SNAPSHOT.jar

Tech: Docker, Docker Swarm, Bash, Linux tc/netem
