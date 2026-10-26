# NVIDIA GPU Plugin for YARN with MIG support for YARN 3.3.0+

This plugin adds support for GPUs with [MIG](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/) on YARN. The built-in YARN GPU plugin does not support MIG enabled GPUs.
This plugin also works with GPUs without MIG or GPUs with MIG disabled but the limitation section still applies. It supports heterogenous environments where
there may be some MIG enabled GPUs and some without MIG. If you are not using MIG enabled GPUs, you should use the built-in YARN GPU plugin.

## Compatibility

It works with Apache YARN 3.3.0+ versions that support the [Pluggable Device Framework](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/PluggableDeviceFramework.html). This plugin requires YARN to be configured with Docker using the NVIDIA Container Toolkit (nvidia-docker2).

## Limitations

Please see the [MIG Application Considerations](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/#app-considerations)
and [CUDA Device Enumeration](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/index.html#cuda-visible-devices).

It is important to note that CUDA 11 only supports enumeration of a single MIG instance. This means that this plugin
only supports 1 GPU per container and the plugin will throw an exception by default if you request more.
It is recommended that you configure YARN to only allow a single GPU be requested. See the yarn config:
```
 yarn.resource-types.nvidia/miggpu.maximum-allocation
```
See [YARN Resource Configuration](https://hadoop.apache.org/docs/r3.3.1/hadoop-yarn/hadoop-yarn-site/ResourceModel.html) for more details.
If you do not configure the maximum allocation and someone requests multiple GPUs, the default behavior is to throw an exception. The user
visible exception is not very useful, as the real exception will be in the nodemanager logs. See the [Configuration](#configuration) section for options
if it throws an exception.

## Building From Source

```
mvn package 
```

This will create a jar `target/yarn-gpu-mig-plugin-1.0.0.jar`. This jar can be installed on your YARN cluster as a plugin.

## Installation

These instructions assume YARN is already installed and configured with Docker enabled using the NVIDIA Container Toolkit (nvidia-docker2).
Enable and configure your [GPUs with MIG](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/index.html) on all of the nodes it applies to.

Install the jar into your Hadoop Cluster, see the [Test and Use Your Own Plugin](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/DevelopYourOwnDevicePlugin.html)
section. This recommends installing it in something like `$HADOOP_COMMOND_HOME/share/hadoop/yarn`.

Configure the device plugin, see the YARN documentation on [Pluggable Device Framework](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/PluggableDeviceFramework.html).

After enabling the framework, enable the plugin in `yarn-site.xml`:

```
<property>
  <name>yarn.nodemanager.pluggable-device-framework.device-classes</name>
  <value>com.nvidia.spark.NvidiaGPUMigPluginForRuntimeV2</value>
</property>

```

Configure YARN to have the new resource type by modifying the `resource-types.xml` file to include:

```
<property>
  <name>yarn.resource-types</name>
  <value>nvidia/miggpu</value>
</property>
```

Restart YARN to pick up any configuration changes.

## Configuration

To change the behavior of throwing when the user allocates multiple GPUs, you can either set a config in the `yarn-site.xml` or set
an environment variable when launching the Spark application. The environment variable will take precendence if both are set.
In either case, `true` means to throw if a user requests multiple GPUs (this is the default), `false`
means it won't throw and if the container is allocated with multiple MIG devices from the same
GPU, it is up to the application to know how to use them.

Config for `yarn-site.xml`:
```
<property>
  <name>com.nvidia.spark.NvidiaGPUMigPluginForRuntimeV2.throwOnMultipleGPUs</name>
  <value>true</value>
</property>
```

Environment variable for Spark application:
```
--conf spark.executorEnv.NVIDIA_MIG_PLUGIN_THROW_ON_MULTIPLE_GPUS=true
```

## Using with Apache Spark on YARN
Spark supports [scheduling GPUs and other custom resources on YARN](http://spark.apache.org/docs/latest/running-on-yarn.html#resource-allocation-and-configuration-overview). There are 2 options for using this plugin with Spark to allocate GPUs with MIG support: 

- Use Spark 3.2.1 or newer and remap the standard Spark `gpu` resource (i.e.: `spark.executor.resource.gpu.amount`) to be the new MIG GPU resource type using:
```
--conf spark.yarn.resourceGpuDeviceName=nvidia/miggpu
```
This means users don't have to change their configs if they were already using the `gpu` resource type.

- Spark applications specify the `nvidia/miggpu` resource type instead of the `gpu` resource type. For this the user has to change the resource
type to `nvidia/miggpu`, update the discovery script, and specify an extra YARN config(`spark.yarn.executor.resource.nvidia/miggpu.amount`).
The command would be something like below (update the amounts according to your setup):
```
 --conf spark.executor.resource.nvidia/miggpu.amount=1 --conf spark.executor.resource.nvidia/miggpu.discoveryScript=./getMIGGPUs --conf spark.task.resource.nvidia/miggpu.amount=0.25 --files ./getMIGGpus --conf spark.yarn.executor.resource.nvidia/miggpu.amount=1
```
Note the getMIGGpus discovery script would is in the `scripts` directory in this repo. It just changes the resource name returned to match
`nvidia/miggpu`.

## Testing
Run a Spark application using the [NVIDIA cuDF plugin for Apache Spark](https://nvidia.github.io/cudf-spark/) and request GPUs
from YARN and verify they use the MIG enabled GPUs.
