---
layout: post
title: FrameTimeline的Jank分类
categories: Android
tags: Android SurfaceFlinger Jank
author: Jasper
---

* content
{:toc}

本文搞懂Android卡顿检测之FrameTimeline中，对Jank的分类判定逻辑，包括SurfaceFrame jank和 DisplayFrame jank。通过jank分类，可以读懂trace图中的jank信息。



# SurfaceFrame Jank

表示应用侧的Jank。

请看下方代码注释。。。

```c++
void SurfaceFrame::classifyJankLocked(int32_t displayFrameJankType, const Fps& refreshRate,
                                      nsecs_t& deadlineDelta) {
    // 必须要先显示出来才能对Jank进行分类
    if (mActuals.presentTime == Fence::SIGNAL_TIME_INVALID) {
        // Cannot do any classification for invalid present time.
        mJankType = JankType::Unknown;
        deadlineDelta = -1;
        return;
    }

    // 预测信息都过期了，显示实在太晚了，直接归入JankType::AppDeadlineMissed
    // 这样的做法有点笼统，但是缺乏预测信息，的确很难分类
    if (mPredictionState == PredictionState::Expired) {
        // We classify prediction expired as AppDeadlineMissed as the
        // TokenManager::kMaxTokens we store is large enough to account for a
        // reasonable app, so prediction expire would mean a huge scheduling delay.
        mJankType = JankType::AppDeadlineMissed;
        deadlineDelta = -1;
        return;
    }

    // 缺乏Token的Surface还不支持Jank检测
    if (mPredictionState == PredictionState::None) {
        // Cannot do jank classification on frames that don't have a token.
        return;
    }

    // 获取应用侧时间的时延
    deadlineDelta = mActuals.endTime - mPredictions.endTime;
    // 获取显示时间的时延
    const nsecs_t presentDelta = mActuals.presentTime - mPredictions.presentTime;
    const nsecs_t deltaToVsync = refreshRate.getPeriodNsecs() > 0
            ? std::abs(presentDelta) % refreshRate.getPeriodNsecs()
            : 0;

    if (deadlineDelta > mJankClassificationThresholds.deadlineThreshold) {
        // 很容易理解，如果应用侧时延过长，认为是未及时完成绘制，即：FrameReadyMetadata::LateFinish
        // 参考前一篇文章的workduration/readyduration的定义，ready表示GPU渲染已经完成
        mFrameReadyMetadata = FrameReadyMetadata::LateFinish;
    } else {
        // 很好，应用侧按时完成了任务
        mFrameReadyMetadata = FrameReadyMetadata::OnTimeFinish;
    }

    if (std::abs(presentDelta) > mJankClassificationThresholds.presentThreshold) {
        // 如果显示时延过长，表示延后显示，即：FramePresentMetadata::LatePresent
        // 如果实际显示时间比预测的时间早，表示提前显示，即：FramePresentMetadata::EarlyPresent
        // FramePresentMetadata::EarlyPresent 是极少发生的，几乎不会发生
        mFramePresentMetadata = presentDelta > 0 ? FramePresentMetadata::LatePresent
                                                 : FramePresentMetadata::EarlyPresent;
    } else {
        // 不延后，表示显示时机刚刚好，用户感受不到掉帧，大多数时候是这样的
        mFramePresentMetadata = FramePresentMetadata::OnTimePresent;
    }

    // 为什么一般都是FramePresentMetadata::OnTimePresent？
    // 因为显示器总是在VSYNC显示一帧图像，而Surface合成并送显之后，会等到下一个VSYNC显示出来
    // 如果一个VSYNC没有显示出来，则会是FramePresentMetadata::LatePresent，而不会是FramePresentMetadata::EarlyPresent

    if (mFramePresentMetadata == FramePresentMetadata::OnTimePresent) {
        // Frames presented on time are not janky.
        // 很好，没有Jank
        mJankType = JankType::None;
    } else if (mFramePresentMetadata == FramePresentMetadata::EarlyPresent) {
        // 不大可能发生，除非发生了错误，比如预测错误、VSYNC错误
        // 实际中，我遇到过VSYNC错误，就是一个VSYNC突然不遵循8ms/16ms周期，而是一个很小的周期，下一帧又恢复正常
        // 预测错误未遇到过
        if (mFrameReadyMetadata == FrameReadyMetadata::OnTimeFinish) {
            // Finish on time, Present early
            if (deltaToVsync < mJankClassificationThresholds.presentThreshold ||
                deltaToVsync >= refreshRate.getPeriodNsecs() -
                                mJankClassificationThresholds.presentThreshold) {
                // Delta factor of vsync
                mJankType = JankType::SurfaceFlingerScheduling;
            } else {
                // Delta not a factor of vsync
                mJankType = JankType::PredictionError;
            }
        } else if (mFrameReadyMetadata == FrameReadyMetadata::LateFinish) {
            // Finish late, Present early
            mJankType = JankType::Unknown;
        }
    } else {
        // 发生了Jank，看看有什么可以纠正的地方？
        if (mLastLatchTime != 0 && mPredictions.endTime <= mLastLatchTime) {
            // Buffer Stuffing.
            // 如果预测的时间比上阀门的时间还要早（所谓上阀门，就是说送显了，即DisplayFrame commit的时间）
            // 说明，这一帧之前还有一帧有待显示，本帧不着急，很可能是Buffer没有申请到而延后
            // 这种做法有武断之处：的确有这种可能，但不一定全是Buffer Stuffing
            mJankType |= JankType::BufferStuffing;
            // In a stuffed state, the frame could be stuck on a dequeue wait for quite some time.
            // Because of this dequeue wait, it can be hard to tell if a frame was genuinely late.
            // We try to do this by moving the deadline. Since the queue could be stuffed by more
            // than one buffer, we take the last latch time as reference and give one vsync
            // worth of time for the frame to be ready.
            // 怎么办呢？延后一个VSYNC周期呗
            nsecs_t adjustedDeadline = mLastLatchTime + refreshRate.getPeriodNsecs();
            if (adjustedDeadline > mActuals.endTime) {
                // 延后一个VSYNC被显示了，说明的确合理，改成FrameReadyMetadata::OnTimeFinish
                // 也就是说，这种情况下，应用侧可以晚一个VSYNC周期ready
                mFrameReadyMetadata = FrameReadyMetadata::OnTimeFinish;
            } else {
                mFrameReadyMetadata = FrameReadyMetadata::LateFinish;
            }
        }
        // 虽然显示延后了，但是应用侧是可能按时ready的，也有可能是被上面代码纠正为FrameReadyMetadata::OnTimeFinish的
        if (mFrameReadyMetadata == FrameReadyMetadata::OnTimeFinish) {
            // Finish on time, Present late
            // 不管怎样，如果的确是FrameReadyMetadata::OnTimeFinish了
            if (displayFrameJankType != JankType::None) {
                // Propagate displayFrame's jank if it exists
                // 使用DisplayFrame的Jank类型填充SurfaceFrame Jank类型，如果有的话
                mJankType |= displayFrameJankType;
            } else {
                // 如果没有知道DisplayFrame的Jank类型
                if (!(mJankType & JankType::BufferStuffing)) {
                    // In a stuffed state, if the app finishes on time and there is no display frame
                    // jank, only buffer stuffing is the root cause of the jank.
                    // 且：SurfaceFrame Jank类型 不与Buffer相关
                    if (deltaToVsync < mJankClassificationThresholds.presentThreshold ||
                        deltaToVsync >= refreshRate.getPeriodNsecs() -
                                        mJankClassificationThresholds.presentThreshold) {
                        // Delta factor of vsync
                        // 发生错误了：1. VSYNC周期出错
                        mJankType |= JankType::SurfaceFlingerScheduling;
                    } else {
                        // Delta not a factor of vsync
                        // 发生错误了：2. 预测错误了
                        mJankType |= JankType::PredictionError;
                    }
                }
            }
        } else if (mFrameReadyMetadata == FrameReadyMetadata::LateFinish) {
            // 不用考虑了，纠正不过来，你就是应用侧时延太长了，判定为JankType::AppDeadlineMissed
            // Finish late, Present late
            mJankType |= JankType::AppDeadlineMissed;
            // Propagate DisplayFrame's jankType if it is janky
            mJankType |= displayFrameJankType;
        }
    }
}
```

# DisplayFrame Jank

表示sf侧的Jank。

请看下面的注释。。。

```c++
void FrameTimeline::DisplayFrame::classifyJank(nsecs_t& deadlineDelta, nsecs_t& deltaToVsync,
                                               nsecs_t previousPresentTime) {
    // 必须是有预测有显示
    if (mPredictionState == PredictionState::Expired ||
        mSurfaceFlingerActuals.presentTime == Fence::SIGNAL_TIME_INVALID) {
        // Cannot do jank classification with expired predictions or invalid signal times. Set the
        // deltas to 0 as both negative and positive deltas are used as real values.
        mJankType = JankType::Unknown;
        deadlineDelta = 0;
        deltaToVsync = 0;
        return;
    }

    // 计算显示时延
    // Delta between the expected present and the actual present
    const nsecs_t presentDelta =
            mSurfaceFlingerActuals.presentTime - mSurfaceFlingerPredictions.presentTime;
    // Sf actual end time represents the CPU end time. In case of HWC, SF's end time would have
    // included the time for composition. However, for GPU composition, the final end time is max(sf
    // end time, gpu fence time).
    // 设定合成时间，优先使用GPU的时间，如果没有，则使用commit的时间
    nsecs_t combinedEndTime = mSurfaceFlingerActuals.endTime;
    if (mGpuFence != FenceTime::NO_FENCE) {
        combinedEndTime = std::max(combinedEndTime, mGpuFence->getSignalTime());
    }
    // 计算合成时延
    deadlineDelta = combinedEndTime - mSurfaceFlingerPredictions.endTime;

    // How far off was the presentDelta when compared to the vsyncPeriod. Used in checking if there
    // was a prediction error or not.
    deltaToVsync = mRefreshRate.getPeriodNsecs() > 0
            ? std::abs(presentDelta) % mRefreshRate.getPeriodNsecs()
            : 0;

    if (std::abs(presentDelta) > mJankClassificationThresholds.presentThreshold) {
        // 显示延后或者提前
        mFramePresentMetadata = presentDelta > 0 ? FramePresentMetadata::LatePresent
                                                 : FramePresentMetadata::EarlyPresent;
    } else {
        // 及时显示
        mFramePresentMetadata = FramePresentMetadata::OnTimePresent;
    }

    if (combinedEndTime > mSurfaceFlingerPredictions.endTime) {
        // sf侧没有work，只有ready，所以，没有按时合成，就是没有按时ready，判定为FrameReadyMetadata::LateFinish
        mFrameReadyMetadata = FrameReadyMetadata::LateFinish;
    } else {
        mFrameReadyMetadata = FrameReadyMetadata::OnTimeFinish;
    }

    if (std::abs(mSurfaceFlingerActuals.startTime - mSurfaceFlingerPredictions.startTime) >
        mJankClassificationThresholds.startThreshold) {
        // 如果sf侧开始太晚，多半是由于sf忙于其它时间，或者CPU繁忙，调度不过来，会发生这样的事情
        mFrameStartMetadata =
                mSurfaceFlingerActuals.startTime > mSurfaceFlingerPredictions.startTime
                ? FrameStartMetadata::LateStart
                : FrameStartMetadata::EarlyStart;
    }

    // 如果没有及时显示，说明发生Jank了
    if (mFramePresentMetadata != FramePresentMetadata::OnTimePresent) {
        // Do jank classification only if present is not on time
        if (mFramePresentMetadata == FramePresentMetadata::EarlyPresent) {
            if (mFrameReadyMetadata == FrameReadyMetadata::OnTimeFinish) {
                // Finish on time, Present early
                if (deltaToVsync < mJankClassificationThresholds.presentThreshold ||
                    deltaToVsync >= (mRefreshRate.getPeriodNsecs() -
                                     mJankClassificationThresholds.presentThreshold)) {
                    // Delta is a factor of vsync if its within the presentTheshold on either side
                    // of the vsyncPeriod. Example: 0-2ms and 9-11ms are both within the threshold
                    // of the vsyncPeriod if the threshold was 2ms and the vsyncPeriod was 11ms.
                    mJankType = JankType::SurfaceFlingerScheduling;
                } else {
                    // Delta is not a factor of vsync,
                    mJankType = JankType::PredictionError;
                }
            } else if (mFrameReadyMetadata == FrameReadyMetadata::LateFinish) {
                // Finish late, Present early
                mJankType = JankType::SurfaceFlingerScheduling;
            } else {
                // Finish time unknown
                mJankType = JankType::Unknown;
            }
        } else if (mFramePresentMetadata == FramePresentMetadata::LatePresent) {
            // 重点：延后显示了
            if (std::abs(mSurfaceFlingerPredictions.presentTime - previousPresentTime) <=
                        mJankClassificationThresholds.presentThreshold ||
                previousPresentTime > mSurfaceFlingerPredictions.presentTime) {
                // The previous frame was either presented in the current frame's expected vsync or
                // it was presented even later than the current frame's expected vsync.
                // 这个有了前面的基础，很容易理解了，当前帧预测显示的时间比上一帧显示还要早，说明上一帧显示太晚了，归入Buffer问题
                mJankType = JankType::SurfaceFlingerStuffing;
            }
            if (mFrameReadyMetadata == FrameReadyMetadata::OnTimeFinish &&
                !(mJankType & JankType::SurfaceFlingerStuffing)) {
                // Finish on time, Present late
                // 如果按时ready了，但还是显示晚了
                if (deltaToVsync < mJankClassificationThresholds.presentThreshold ||
                    deltaToVsync >= (mRefreshRate.getPeriodNsecs() -
                                     mJankClassificationThresholds.presentThreshold)) {
                    // Delta is a factor of vsync if its within the presentTheshold on either side
                    // of the vsyncPeriod. Example: 0-2ms and 9-11ms are both within the threshold
                    // of the vsyncPeriod if the threshold was 2ms and the vsyncPeriod was 11ms.
                    // 说明是显示屏的问题，也就是HAL接口的问题，或者是屏幕驱动的问题
                    mJankType = JankType::DisplayHAL;
                } else {
                    // Delta is not a factor of vsync
                    // 如果不是显示屏的问题，只能是预测错了，哈哈，纯粹排除法
                    mJankType = JankType::PredictionError;
                }
            } else if (mFrameReadyMetadata == FrameReadyMetadata::LateFinish) {
                // sf侧ready晚了，什么原因呢？
                if (!(mJankType & JankType::SurfaceFlingerStuffing) ||
                    mSurfaceFlingerActuals.presentTime - previousPresentTime >
                            mRefreshRate.getPeriodNsecs() +
                                    mJankClassificationThresholds.presentThreshold) {
                    // Classify CPU vs GPU if SF wasn't stuffed or if SF was stuffed but this frame
                    // was presented more than a vsync late.
                    // 如果不是Buffer问题，就只能是GPU或者CPU的问题了，排除法嘛（哈哈），反正我不考虑IO、Lock等等那些东西
                    if (mGpuFence != FenceTime::NO_FENCE &&
                        mSurfaceFlingerActuals.endTime - mSurfaceFlingerActuals.startTime <
                                mRefreshRate.getPeriodNsecs()) {
                        // If SF was in GPU composition and the CPU work finished before the vsync
                        // period, classify it as GPU deadline missed.
                        // GPU Fence来晚了，GPU性能不行，导致sf合成延时了
                        mJankType = JankType::SurfaceFlingerGpuDeadlineMissed;
                    } else {
                        // 只能是CPU问题了，还想赖谁！
                        mJankType = JankType::SurfaceFlingerCpuDeadlineMissed;
                    }
                }
            } else {
                 // Finish time unknown
                 mJankType = JankType::Unknown;
			}
		} else {
			// Present unknown
			mJankType = JankType::Unknown;
		}
	}
}
```

# 总结

要么应用侧延后了，要么sf侧延后了。   
应用侧延后的原因，只标定为AppDeadlineMissed，至于什么更细的原因，没有做细分。  
sf侧延后的原因莫非：1. GPU 2. CPU。

应用侧原因是可以细分的，是一个值得挖掘的地方。

全写在上文的中文备注，有错烦请call me。

# 参考

[http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/services/surfaceflinger/](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/services/surfaceflinger/)
