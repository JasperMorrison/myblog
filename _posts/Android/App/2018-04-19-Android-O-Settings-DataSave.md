---
layout: post
title: Android O Settings DataSave
categories: "Android"
tags: android Settings DataSave
author: Jasper
---

* content
{:toc}

这里记录，基于Android O，从Settings入手，介绍Android DataSave是什么，如何设置，实现原理。



## 不受流量限制

进入对应设置页面的步骤：设置 - 应用和通知 - 高级 - 特殊应用权限 - 不受流量限制。
如果在这里设置了允许，那么，应用可以Doze模式下不受流量限制地获得数据网络访问的权限。
可以肆无忌惮的在后台跑流量了。

## Settings如何实现界面？

对应的界面类：`com.android.settings.datausage.UnrestrictedDataAccess`

```java
    @Override
    public void onCreate(Bundle icicle) {
        super.onCreate(icicle);
        setAnimationAllowed(true);//允许使用动画，等待过程中转圈
        setPreferenceScreen(getPreferenceManager().createPreferenceScreen(getContext()));
        mApplicationsState = ApplicationsState.getInstance(// 用于获得App的基本信息，label，icon之类的
                (Application) getContext().getApplicationContext());
        mDataSaverBackend = new DataSaverBackend(getContext());// 用于获得DataSave的配置信息，从NetworkPolicy服务获得
        mDataUsageBridge = new AppStateDataUsageBridge(mApplicationsState, this, mDataSaverBackend);// 连接上面两个部分的辅助类
        mSession = mApplicationsState.newSession(this);// 建立一个异步加载应用信息的Session
        mShowSystem = icicle != null && icicle.getBoolean(EXTRA_SHOW_SYSTEM);// 是否显示系统应用的配置信息
        mFilter = mShowSystem ? ApplicationsState.FILTER_ALL_ENABLED // 一个自定义的过滤器，过滤系统应用
                : ApplicationsState.FILTER_DOWNLOADED_AND_LAUNCHER;
        setHasOptionsMenu(true);
    }
```


```java

    @Override
    public void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putBoolean(EXTRA_SHOW_SYSTEM, mShowSystem);// 保存界面的临时状态，当从后台恢复时能正常显示
    }

    @Override
    public void onViewCreated(View view, Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        setLoading(true, false); // 开始转圈圈
    }

    @Override
    public void onResume() {
        super.onResume();
        mSession.resume(); // 异步加载信息通道打开
        mDataUsageBridge.resume(); // 开始异步加载信息，AOSP中，这里面有个异步Bug
    }

    @Override
    public void onExtraInfoUpdated() {
        mExtraLoaded = true;
        rebuild(); // 显示列表
    }
```

假设现在所有内容都已经加载完了，也不考虑异步加载问题。看看界面如何显示？

```java
    @Override
    public void onRebuildComplete(ArrayList<AppEntry> apps) {
        if (getContext() == null) return;
        cacheRemoveAllPrefs(getPreferenceScreen()); 
        // 每次都替换一个Preference cache，将所有找到的preference都放进去
        // 这样做的目的是不改变界面上现有的preference，只添加没有的
        final int N = apps.size();
        for (int i = 0; i < N; i++) {
            AppEntry entry = apps.get(i);
            if (!shouldAddPreference(entry)) { // 做一个简单的判断，应该Google的程序员发现了一个莫名其妙其妙的Bug而做的限制
                continue;
            }
            String key = entry.info.packageName + "|" + entry.info.uid;
            AccessPreference preference = (AccessPreference) getCachedPreference(key); //从刚才建立的Cache中拿到Preference
            if (preference == null) {
                preference = new AccessPreference(getPrefContext(), entry);
                preference.setKey(key);
                preference.setOnPreferenceChangeListener(this);
                getPreferenceScreen().addPreference(preference);// 添加一行
            } else {
                preference.reuse(); // 重用
            }
            preference.setOrder(i); // 给一个顺序它，这样做的目的是，apps已经排过序，列表的位置也应该符合原来的排序
        }
        setLoading(false, true); // 不要转圈圈了
        removeCachedPrefs(getPreferenceScreen()); // 删除缓存，因为没有必要存放了
    }
```

## 填充AppEntry和State

AppEntry，这个就没什么好说的，都是些常规的获取app信息，重要是State。
```java
    public void onResume() {
        super.onResume();
        mSession.resume(); // 加载App信息
        mDataUsageBridge.resume(); // 加载State信息
    }
```

State的填充：
`com.android.settings.datausage.AppStateDataUsageBridge#loadAllExtraInfo`
```java
    @Override
    protected void loadAllExtraInfo() {
        ArrayList<AppEntry> apps = mAppSession.getAllApps();
        final int N = apps.size();
        for (int i = 0; i < N; i++) {
            AppEntry app = apps.get(i);
            app.extraInfo = new DataUsageState(mDataSaverBackend.isWhitelisted(app.info.uid), // 判断NetworkPolicy状态
                    mDataSaverBackend.isBlacklisted(app.info.uid));
        }
    }
```

```java
    private void loadWhitelist() {
        if (mWhitelistInitialized) return;

        for (int uid : mPolicyManager.getUidsWithPolicy(POLICY_ALLOW_METERED_BACKGROUND)) { // 这里进入Policy的世界
            mUidPolicies.put(uid, POLICY_ALLOW_METERED_BACKGROUND);
        }
        mWhitelistInitialized = true;
    }
```

```java
    com.android.server.net.NetworkPolicyManagerService#getUidsWithPolicy
    @Override
    public int[] getUidsWithPolicy(int policy) {
        mContext.enforceCallingOrSelfPermission(MANAGE_NETWORK_POLICY, TAG);

        int[] uids = new int[0];
        synchronized (mUidRulesFirstLock) {
            for (int i = 0; i < mUidPolicy.size(); i++) {
                final int uid = mUidPolicy.keyAt(i);
                final int uidPolicy = mUidPolicy.valueAt(i);
                if ((policy == POLICY_NONE && uidPolicy == POLICY_NONE) ||
                        (uidPolicy & policy) != 0) { // 一个二进制位代表一种policy类型
                    uids = appendInt(uids, uid);
                }
            }
        }
        return uids;
    }
```

## Network Policy

这里看看App的 Network Policy 是如何设置的

从上面的获取过程知道，所有的policy都存放在一个数组里面：
```java
    /** Defined UID policies. */
    @GuardedBy("mUidRulesFirstLock") final SparseIntArray mUidPolicy = new SparseIntArray();
```
谁设置了Policy？

```java
    android.net.NetworkPolicyManager#setUidPolicy
    /**
     * Set policy flags for specific UID.
     *
     * @param policy should be {@link #POLICY_NONE} or any combination of {@code POLICY_} flags,
     *     although it is not validated.
     */
    public void setUidPolicy(int uid, int policy) {
        try {
            mService.setUidPolicy(uid, policy);
        } catch (RemoteException e) {
            throw e.rethrowFromSystemServer();
        }
    }
```

```java 
    private void setUidPolicyUncheckedUL(int uid, int policy, boolean persist) {
        if (policy == POLICY_NONE) {
            mUidPolicy.delete(uid);
        } else {
            mUidPolicy.put(uid, policy); // 直接put进入，没有任何的按位或，相当于只是用了一个二进制位，说白了，只支持一种policy类型，那就是POLICY_ALLOW_METERED_BACKGROUND
        }

        // uid policy changed, recompute rules and persist policy.
        updateRulesForDataUsageRestrictionsUL(uid);
        if (persist) {
            synchronized (mNetworkPoliciesSecondLock) {
                writePolicyAL();
            }
        }
    }
```

## 让Network Policy支持更多的policy

那么，需要将函数的实现体修改一下。共有几个内容：
1. Network Policy服务启动时，按二进制位处理各种policy
2. set函数添加或功能，而不是单纯的.put进列表
3. 其它辅助函数体的修改

## METERED_BACKGROUND policy到底干了啥

一路跟下去，能很顺利的看到，它是取设置iptables的 bandwidth

`mConnector.execute("bandwidth", suffix + chain, uid);`

所谓的iptables的bandwidth，其实是用iptables设置其带宽限制。
类似的，还可以iptables的firewall。

要熟悉上述信息，需要熟悉linux/Android  iptables， 以及Android Netd

下次有时间，就放一篇关于用防火墙限制应用联网的改造blog。