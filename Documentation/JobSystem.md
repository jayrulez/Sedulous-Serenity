# Sedulous.Jobs

A thread-safe, multi-threaded job scheduling and execution system. Provides work distribution across background threads with support for dependencies, priorities, and main-thread execution.

## Overview

```
JobSystem
├── MainThreadWorker     (runs on main thread)
│   └── Processes jobs with RunOnMainThread flag
├── BackgroundWorker[0]  (background thread)
├── BackgroundWorker[1]  (background thread)
└── BackgroundWorker[N]  (background thread)
```

## Core Types

| Type | Purpose |
|------|---------|
| `JobSystem` | Central manager. Creates workers, dispatches jobs, manages lifecycle. |
| `JobBase` | Abstract base for all jobs. Provides dependency tracking and state. |
| `Job` | Abstract user-defined job. Override `OnExecute()` for custom work. |
| `Job<T>` | Job that returns a result of type T. |
| `DelegateJob` | Executes a delegate without return value. |
| `DelegateJob<T>` | Executes a delegate with return value and completion callback. |
| `JobGroup` | Executes multiple jobs sequentially as a single unit. |
| `JobPriority` | Priority levels: Normal, High. |
| `JobState` | Execution state: Pending, Running, Succeeded, Canceled. |
| `JobFlags` | Behavior flags: None, RunOnMainThread, AutoRelease. |

## Basic Usage

### Creating a Custom Job

```beef
class MyJob : Job
{
    private int mValue;

    public this(int value) : base("MyJob", .None)
    {
        mValue = value;
    }

    protected override void OnExecute()
    {
        // Your work here
        Console.WriteLine($"Processing: {mValue}");
    }
}
```

### Running Jobs

```beef
// Create and start job system
let jobSystem = new JobSystem(logger, 4);  // 4 worker threads
jobSystem.Startup();

// Add a custom job
let job = new MyJob(42);
jobSystem.AddJob(job);

// Main loop - must call Update() each frame
while (running)
{
    jobSystem.Update();
    Thread.Sleep(16);
}

// Cleanup
jobSystem.Shutdown();
```

### Delegate Jobs

```beef
// Simple delegate job
jobSystem.AddJob(new () => {
    Console.WriteLine("Quick task");
}, true, "QuickTask");

// Delegate with result and callback
jobSystem.AddJob<int32>(
    new () => { return 42; },
    true,
    "ComputeJob",
    .None,
    new [&](result) => {
        Console.WriteLine($"Result: {result}");
    },
    true
);
```

### Main Thread Jobs

Jobs with `RunOnMainThread` flag execute during `Update()` on the main thread:

```beef
let job = new MyJob(.RunOnMainThread);
jobSystem.AddJob(job);
```

## Job Dependencies

Jobs can depend on other jobs. A job only runs when all its dependencies have succeeded.

```beef
let job1 = new FetchJob();
let job2 = new ProcessJob();
let job3 = new SaveJob();

// Set up dependency chain: job1 -> job2 -> job3
job2.AddDependency(job1);
job3.AddDependency(job2);

// Add in any order - dependencies control execution order
jobSystem.AddJob(job3);
jobSystem.AddJob(job2);
jobSystem.AddJob(job1);
```

**Dependency Rules:**
- Jobs only run when `IsReady()` returns true (all dependencies succeeded)
- Canceling a job cascades to all dependent jobs
- Circular dependencies cause a fatal error
- Self-dependency causes a fatal error

## Job Groups

Execute multiple jobs sequentially as a single atomic unit:

```beef
let group = new JobGroup("DataPipeline");
group.AddJob(new LoadDataJob());
group.AddJob(new ProcessDataJob());
group.AddJob(new SaveDataJob());
jobSystem.AddJob(group);
```

**Group Behavior:**
- Jobs execute in order on the same worker
- Cannot add jobs after the group starts running
- All jobs must be added before adding group to system

## Job States

```
Pending   → Running → Succeeded
              ↓
           Canceled
```

| State | Description |
|-------|-------------|
| `Pending` | Waiting in queue, not yet started |
| `Running` | Currently executing |
| `Succeeded` | Completed successfully |
| `Canceled` | Was canceled (directly or via dependency) |

## Job Flags

| Flag | Description |
|------|-------------|
| `None` | Default behavior (run on background thread) |
| `RunOnMainThread` | Execute on main thread during `Update()` |
| `AutoRelease` | Automatically release job when completed |

## Waiting for Completion

```beef
// Blocking wait (not recommended for frame-based apps)
job.Wait();

// For jobs with results
let resultJob = new MyResultJob();
let result = resultJob.WaitForResult();

// Frame-based pattern (recommended)
while (!job.IsCompleted())
{
    jobSystem.Update();
    Thread.Sleep(10);
}
```

## Thread Pool Management

### Worker Count

```beef
// Auto-detect (CPU cores - 1, minimum 2)
let jobSystem = new JobSystem(logger);

// Specify count
let jobSystem = new JobSystem(logger, 4);

// Main-thread only (0 background workers)
let jobSystem = new JobSystem(logger, 0);
```

### Worker Recovery

Background workers marked as `Persistent` are automatically restarted if their thread dies. The `Update()` method monitors worker health and recreates dead persistent workers.

## Memory Management

Jobs use reference counting for safe cleanup across threads:

```beef
// AutoRelease pattern - JobSystem manages deletion
jobSystem.AddJob(new () => { /* work */ }, false, "Job", .AutoRelease);

// Manual management - caller must manage lifetime
let job = new MyJob();
defer job.ReleaseRefNoDelete();
jobSystem.AddJob(job);
```

## JobSystem API

### Lifecycle

```beef
void Startup();           // Initialize workers, start processing
void Shutdown();          // Stop all workers, cancel pending jobs
void Update();            // Call once per frame from main thread
```

### Adding Jobs

```beef
void AddJob(JobBase job);
void AddJobs(Span<JobBase> jobs);
void AddJob(delegate void() work, bool autoDelete, StringView name, JobFlags flags = .AutoRelease);
void AddJob<T>(delegate T() work, bool autoDelete, StringView name, JobFlags flags,
               delegate void(T) onCompleted, bool autoDeleteOnCompleted);
```

### Properties

```beef
bool IsRunning { get; }      // Is system active
int WorkerCount { get; }     // Number of background workers
ILogger Logger { get; }      // Logging interface
```

## Best Practices

1. **Always call `Update()` from main thread** in your frame loop
2. **Use `AutoRelease` for delegate jobs** to avoid manual cleanup
3. **Set up dependencies before adding jobs** to JobSystem
4. **Use `JobGroup` for sequential tasks** rather than manual chaining
5. **Let JobSystem auto-detect worker count** in most cases
6. **Handle results with callbacks** rather than blocking `Wait()`
7. **Don't add jobs to `JobGroup` after it starts**
8. **Use proper `Startup()`/`Shutdown()` cycles**

## Project Structure

```
Code/Sedulous/Sedulous.Jobs/src/
├── JobSystem.bf           - Central job manager
├── JobBase.bf             - Abstract base for all jobs
├── Job.bf                 - User-defined job base class
├── DelegateJob.bf         - Delegate-based jobs
├── JobGroup.bf            - Sequential job group
├── JobPriority.bf         - Priority enum
├── JobState.bf            - State enum
├── JobFlags.bf            - Flags enum
├── JobRunResult.bf        - Execution result enum
├── Worker.bf              - Base worker class
├── BackgroundWorker.bf    - Background thread worker
└── MainThreadWorker.bf    - Main thread worker
```
