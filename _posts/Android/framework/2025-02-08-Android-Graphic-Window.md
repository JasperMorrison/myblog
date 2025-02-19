---
layout: post
title: Android窗口管理-window layer布局构建
categories: Android
tags: Android 图形栈 窗口管理 DisplayArea
author: Jasper
---

* content
{:toc}

本文介绍 window layer布局，即 DisplayArea树 构建方法。有别于其它文章的介绍，从窗口层级的角度，探索其本身的设计思想，具有鲜明的原创特征。通过本文，我敢说window layer布局，或者说 窗口层级结构，比DisplayArea树更直观易懂。



# 1. dumpsys

> dumpsys window containers

![](/images/Android/framework/Android-DisplayArea-dump.png)

先读懂上面dump信息的含义，我们再看代码实现。

上图是一台设备的Display 0的窗口层级结构，可以看到，窗口层级结构是层层嵌套的。

Display 0下面，有2个DisplayArea，和一个Leaf（还没讲到添加window，暂且可以理解为，为了保证结构的完整性，属于特殊的DisplayArea），分别是  
1. #2 Leaf:36:36
2. #1 HideDisplayCoutout:32:35
3. #0 WindowedMagnification:0:31

一个DisplayArea有这样的显示结构：

\# + index + Name + minLayer + maxLayer

index：表示子节点在数组中的下标，**DisplayArea就是某层window layer的节点**  
Name：表示子节点的名字  
minLayer：表示所覆盖的window layer的下限  
maxLayer：表示所覆盖的window layer的上限

window layer：表示window的层级，这里是从0-36，共37层，后面我就简称layer，或者层级吧。

**某个window layer，或者相邻的window layer上，都是以Leaf叶节点结束的，如果没有DisplayArea子节点，则window layer会直接挂一个Leaf。**

**记住，**我们是以window layer的维度去理解窗口层级结构的。

# Feature（重点）

**Feature是设计思想的出发点，它通过特性来作用于layer和后续的Feature，是理解窗口层级结构的重点。**先弄明白这个关键点，再深入研究会很简单，这也就是本文与其它文章不同的地方。

Feature有别于我们说的“系统Feature”所表示的某个系统功能，这里的Feature，更多的是表示具有**相同特性**的窗口，不同类型的窗口，可能具备相同的特性，它们可以放在**layer范围**内。Feature的特性会作用于layer和后续添加进来的Feature：

![](/images/Android/framework/Android-DisplayArea-feature-action.png)

**记住，**如果相同Feature的窗口可以放在同一个**layer范围**内，那么，我们就用一个DisplayArea节点来管理它们。于是，就有了 \[minLayer: maxLayer\]的范围表示法。

特别的，Feature受到先添加进来的Feature的**layer范围**约束，如果前一个Feature在此**layer范围**内不是连续的DisplayArea，则本Feature也需要拆分。

**举个例子**

按照Feature特性对layer的影响，假设有下面的层级结构图：

---|---|---
layer|Feature1|Feature2
36|DisplayArea1|DisplayArea3|
35|DisplayArea1|DisplayArea3|
34|DisplayArea2|DisplayArea3|

但是，Feature2会受Feature1的约束，Feature1在34层不连续了，Feature2就不能继续使用DisplayArea3来管理window了，改成：

---|---|---
layer|Feature1|Feature2
36|DisplayArea1|DisplayArea3|
35|DisplayArea1|DisplayArea3|
34|DisplayArea2|DisplayArea4|

DisplayArea2也可以不存在，表示Feature1不需要作用于第34层layer，得到：

---|---|---
layer|Feature1|Feature2
36|DisplayArea1|DisplayArea3|
35|DisplayArea1|DisplayArea3|
34||DisplayArea4|

最终得到这样的树状结构： 

![](/images/Android/framework/Android-DisplayArea-tree.png)

在构建时，DisplayArea被PendingArea表示，完成后增加Leaf（真实的DisplayArea），并将PendingArea替换为它所属的Feature，最终会得到：

![](/images/Android/framework/Android-DisplayArea-Feature-tree.png)

# 构建window layer布局

有了上面的两个**记住**要点，构建layer布局就相当简单了，步骤如下：

1. 为系统中指定一些Feature，对于每一个Feature，我们都明确标明它需要在哪些layer层级上布置window；
2. 遍历这些Feature，为它们在需要布置window的layer层级上创建DisplayArea节点；
3. 对于同一个Feature，如果它要求连续多个layer都放置window，用同一个DisplayArea；（**这里是关键**）
4. 如果该Feature前面添加进来的Feature不连续，则分割DisplayArea。

# 代码注释

在创建DisplayArea之前，会先使用PendingArea来构建层级结构，PendingArea是临时的，最终会转换成DisplayArea。

```java
// 前置变量：略

PendingArea[] areaForLayer = new PendingArea[maxWindowLayerCount];
final PendingArea root = new PendingArea(null, 0, null);
Arrays.fill(areaForLayer, root);

// Create DisplayAreas to cover all defined features.
final int size = mFeatures.size();
for (int i = 0; i < size; i++) {
    // Traverse the features with the order they are defined, so that the early defined
    // feature will be on the top in the hierarchy.
    final Feature feature = mFeatures.get(i);
    PendingArea featureArea = null;
    for (int layer = 0; layer < maxWindowLayerCount; layer++) {
        if (feature.mWindowLayers[layer]) {
            // This feature will be applied to this window layer.
            //
            // We need to find a DisplayArea for it:
            // We can reuse the existing one if it was created for this feature for the
            // previous layer AND the last feature that applied to the previous layer is
            // the same as the feature that applied to the current layer (so they are ok
            // to share the same parent DisplayArea).
            if (featureArea == null || featureArea.mParent != areaForLayer[layer]) {
                // No suitable DisplayArea:
                // Create a new one under the previous area (as parent) for this layer.
                featureArea = new PendingArea(feature, layer, areaForLayer[layer]);
                areaForLayer[layer].mChildren.add(featureArea);
            }
            areaForLayer[layer] = featureArea;
        } else {
            // This feature won't be applied to this window layer. If it needs to be
            // applied to the next layer, we will need to create a new DisplayArea for
            // that.
            featureArea = null;
        }
    }
}

// 创建leaf：略
// 转换为DisplayArea：略
```

1. 先定义layer层级结构，PendingArea[] areaForLayer，共37个；（Android13有39个）  
2. 为所有layer都赋值一个root对象，PendingArea root（回想上面的两个**记住**，连续的layer用同一个PendingArea）  
3. 遍历Feature，根据mFeatures.size()  
4. 在每一个layer上，做检查，for (int layer = 0; layer < maxWindowLayerCount; layer++)  
5. 如果这个Feature需要在layer上放置window，feature.mWindowLayers[layer] == true，则考虑是否需要创建新的PendingArea  
6. 如果还没PendingArea，featureArea == null，创建一个加进去，设置父亲  
7. 如果连续的layer都需要存放，featureArea.mParent != areaForLayer[layer]，使用同一个PendingArea  
8. 完毕。。。

# 总结

根据上述介绍的设计思想，再回头看看文章开头的dump信息，是否一目了然，总结起来三句话。

1. window layer使用DisplayArea节点来管理着Feature需要放置window的区域；
2. 如果同一个Feature需要连续多个layer放置window，则使用同一个DisplayArea，并受前一个Feature的layer范围约束；
3. 所有DisplayArea节点，或者空闲的layer区间，后面都要挂一个Leaf节点；

# 参考

[DisplayAreaPolicyBuilder](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/services/core/java/com/android/server/wm/DisplayAreaPolicyBuilder.java)
