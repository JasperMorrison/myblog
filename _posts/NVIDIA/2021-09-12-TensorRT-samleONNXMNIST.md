---
layout: post
title: TensorRT 加载ONNX进行推理 sampleONNXMNIST
categories: NVIDIA 翻译
tags: AI NVIDIA DeepLearning TensorRT
author: Jasper
---

* content
{:toc}


本文对TensorRT sampleONNXMNIST进行了介绍和实践，与官方无异，但其中有一些实践经验值得参考。



# 1. 本地实验环境

CUDA-10.2  
cuDNN-7.6.5  
Docker-20+  

# 2. 参考

TensorRT文档：https://docs.nvidia.com/deeplearning/tensorrt/  
TensorRT代码：https://github.com/NVIDIA/TensorRT/tree/release/7.0  
Sample代码：https://github.com/NVIDIA/TensorRT/tree/master/samples/sampleOnnxMNIST  
Install Guide: https://docs.nvidia.com/deeplearning/tensorrt/quick-start-guide/index.html#container-install  
Docker：https://ngc.nvidia.com/catalog/containers/nvidia:tensorrt  
Docker-Tag:https://docs.nvidia.com/deeplearning/tensorrt/container-release-notes/index.html  
20.03: https://docs.nvidia.com/deeplearning/tensorrt/container-release-notes/rel_20-03.html#rel_20-03  

# 3. 环境准备
`docker pull nvcr.io/nvidia/tensorrt:20.03-py3`

`nvidia-docker run -it --rm nvcr.io/nvidia/tensorrt:20.03-py3 bash`

```
root@bbc48ebe567d:/workspace/tensorrt# ll 
lrwxrwxrwx  1 root root   34 Mar  2  2020 TensorRT-Release-Notes.pdf -> doc/pdf/TensorRT-Release-Notes.pdf
drwxrwxrwx  2 root root 4096 Mar  2  2020 bin/
lrwxrwxrwx  1 root root   18 Mar  2  2020 data -> /opt/tensorrt/data/
lrwxrwxrwx  1 root root   32 Mar  2  2020 doc -> /usr/share/doc/tensorrt-7.0.0.11/
drwxrwxrwx 26 root root 4096 Mar  2  2020 samples/
```

```
cd /workspace/tensorrt/samples
make -j4
cd /workspace/tensorrt/
./bin/sample_onnx_mnist
```

如果想加快编译速度，修改Makefile文件，将samples改成需要的目标。

# 4. sampleONNXMNIST

## 4.1. 准备

```
cd /opt/tensorrt/data/mnist/
python download_pgms.py
cd /workspace/tensorrt/
./bin/sample_onnx_mnist
```

```
root@11f7ea702182:/workspace/tensorrt# ./bin/sample_onnx_mnist
&&&& RUNNING TensorRT.sample_onnx_mnist # ./bin/sample_onnx_mnist
[09/12/2021-09:48:31] [I] Building and running a GPU inference engine for Onnx MNIST
----------------------------------------------------------------
Input filename:   data/mnist/mnist.onnx
ONNX IR version:  0.0.3
Opset version:    8
Producer name:    CNTK
Producer version: 2.5.1
Domain:           ai.cntk
Model version:    1
Doc string:       
----------------------------------------------------------------
[09/12/2021-09:48:32] [W] [TRT] onnx2trt_utils.cpp:198: Your ONNX model has been generated with INT64 weights, while TensorRT does not natively support INT64. Attempting to cast down to INT32.
[09/12/2021-09:48:32] [W] [TRT] onnx2trt_utils.cpp:198: Your ONNX model has been generated with INT64 weights, while TensorRT does not natively support INT64. Attempting to cast down to INT32.
[09/12/2021-09:48:37] [I] [TRT] Detected 1 inputs and 1 output network tensors.
[09/12/2021-09:48:37] [W] [TRT] Current optimization profile is: 0. Please ensure there are no enqueued operations pending in this context prior to switching profiles
[09/12/2021-09:48:37] [I] Input:
[09/12/2021-09:48:37] [I] @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@#=.  +*=#@@@@@@@
@@@@@@@@@@@*   :.   -@@@@@@@
@@@@@@@@@@#  :#@@:  +@@@@@@@
@@@@@@@@@*  :@@@*  .@@@@@@@@
@@@@@@@@=  =@@@@.  *@@@@@@@@
@@@@@@@=  -@@@@*  =@@@@@@@@@
@@@@@@@  -@@@%:  -@@@@@@@@@@
@@@@@@%  %%+:    *@@@@@@@@@@
@@@@@@@      ..  @@@@@@@@@@@
@@@@@@@#  .=%%: =@@@@@@@@@@@
@@@@@@@@@@@@@#  +@@@@@@@@@@@
@@@@@@@@@@@@@#  @@@@@@@@@@@@
@@@@@@@@@@@@@@  @@@@@@@@@@@@
@@@@@@@@@@@@@#  @@@@@@@@@@@@
@@@@@@@@@@@@@+  @@@@@@@@@@@@
@@@@@@@@@@@@@%  @@@@@@@@@@@@
@@@@@@@@@@@@@@. #@@@@@@@@@@@
@@@@@@@@@@@@@@* :%@@@@@@@@@@
@@@@@@@@@@@@@@@: -@@@@@@@@@@
@@@@@@@@@@@@@@@@= %@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@

[09/12/2021-09:48:37] [I] Output:
[09/12/2021-09:48:37] [I]  Prob 0  0.0000 Class 0: 
[09/12/2021-09:48:37] [I]  Prob 1  0.0000 Class 1: 
[09/12/2021-09:48:37] [I]  Prob 2  0.0000 Class 2: 
[09/12/2021-09:48:37] [I]  Prob 3  0.0000 Class 3: 
[09/12/2021-09:48:37] [I]  Prob 4  0.0000 Class 4: 
[09/12/2021-09:48:37] [I]  Prob 5  0.0000 Class 5: 
[09/12/2021-09:48:37] [I]  Prob 6  0.0000 Class 6: 
[09/12/2021-09:48:37] [I]  Prob 7  0.0000 Class 7: 
[09/12/2021-09:48:37] [I]  Prob 8  0.0000 Class 8: 
[09/12/2021-09:48:37] [I]  Prob 9  1.0000 Class 9: **********
[09/12/2021-09:48:37] [I] 
&&&& PASSED TensorRT.sample_onnx_mnist # ./bin/sample_onnx_mnist
```

## 4.2. ONNX-model to TensorRT-network

利用ONNX parser，将ONNX模型转换为TensorRT的network。

`auto parser = nvonnxparser::createParser(*network, gLogger.getTRTLogger());`

```c++
if (!parser->parseFromFile(model_file, static_cast<int>(gLogger.getReportableSeverity())))
{
	  string msg("failed to parse onnx file");
	  gLogger->log(nvinfer1::ILogger::Severity::kERROR, msg.c_str());
	  exit(EXIT_FAILURE);
}
```

显示network信息，包括层、维度等。

```c++
parser->reportParsingInfo();
```

TensorRT network 创建后，可以创建 TensorRT engine 来进行推理.

## 4.3. 生成engine

`IBuilder* builder = createInferBuilder(gLogger);`

`nvinfer1::ICudaEngine* engine = builder->buildCudaEngine(*network);`

通过检查engine的输出是否符合预期来判断engine的创建是否正确。

## 4.4. 执行推理

[Performing Inference In C++](https://docs.nvidia.com/deeplearning/sdk/tensorrt-developer-guide/index.html#perform_inference_c).

**Note:** 注意对数据进行预处理，并使其符合网络的输入格式， 本样例中, 输入是 PGM (portable graymap) format. 输入image满足 `1x28x28`，归一化到 `[0,1]`.

## 4.5. 代码结构

### 4.5.1. main


```c++
    SampleOnnxMNIST sample(initializeSampleParams(args));
    if (!sample.build())
    if (!sample.infer())
```

### 4.5.2. 参数


```c++
    samplesCommon::OnnxSampleParams params;
    params.dataDirs.push_back("data/mnist/");
    params.dataDirs.push_back("data/samples/mnist/");
    params.onnxFileName = "mnist.onnx";
    params.inputTensorNames.push_back("Input3");
    params.batchSize = 1;
    params.outputTensorNames.push_back("Plus214_Output_0");
    params.dlaCore = args.useDLACore;
    params.int8 = args.runInInt8;
    params.fp16 = args.runInFp16;
}
```

关注点：  
1. 数据和模型路径
2. 输入/输出Tensor名称
3. batchSize
4. 运行精度

这里的运行精度只是简单的映射，不是量化。量化参考sampleINT8.

### 4.5.3. build

```c++
    auto builder = SampleUniquePtr<nvinfer1::IBuilder>(nvinfer1::createInferBuilder(gLogger.getTRTLogger()));
    const auto explicitBatch = 1U << static_cast<uint32_t>(NetworkDefinitionCreationFlag::kEXPLICIT_BATCH);     
    auto network = SampleUniquePtr<nvinfer1::INetworkDefinition>(builder->createNetworkV2(explicitBatch));
    auto config = SampleUniquePtr<nvinfer1::IBuilderConfig>(builder->createBuilderConfig());
    auto parser = SampleUniquePtr<nvonnxparser::IParser>(nvonnxparser::createParser(*network, gLogger.getTRTLogger()));
    auto constructed = constructNetwork(builder, network, config, parser);
    builder->buildEngineWithConfig(*network, *config), samplesCommon::InferDeleter());
    mInputDims = network->getInput(0)->getDimensions();
    mOutputDims = network->getOutput(0)->getDimensions();
```

创建IBuilder、INetworkDefinition、IBuilderConfig、IParser对象。

利用parser->parseFromFile，解析ONNX模型。

利用builder->buildEngineWithConfig，创建engine。

最后，验证输入输出。

### 4.5.4. infer


```c++
    samplesCommon::BufferManager buffers(mEngine, mParams.batchSize);
    auto context = SampleUniquePtr<nvinfer1::IExecutionContext>(mEngine->createExecutionContext());

    if (!processInput(buffers))
    buffers.copyInputToDevice();
    bool status = context->executeV2(buffers.getDeviceBindings().data());
    buffers.copyOutputToHost();
    if (!verifyOutput(buffers))
```

创建一个buffers，和一个可执行上下文IExecutionContext。

将输入填充到buffers，copy到Device（即GPU）。

利用上下文和buffers-device-data，执行推理动作。

将推理结果从GPU copy回host。

验证输出结果。

buffers是一个管理对象，见buffer.h，管理包括DeviceBuffer（cudaMalloc）、HostBuffer（malloc）两种类型的buffer。

# 5. 总结

sampleONNXMNIST提供了一个使用TensorRT加载ONNX模型，生成engine来进行推理的样例，是一个较完整的TensorRT-API的使用例子。
