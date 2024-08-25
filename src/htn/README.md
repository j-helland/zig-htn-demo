# Hierarchical Task Network (HTN)

This HTN implementation is based on Troy Humphreys' examples in [Exploring HTN Planners through Example](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf).

The basic idea is to encode the world into a simple world state representation that the HTN planner can reason about.
The world state itself is essentially just an array of `WorldStateValue` enum values indexed by `WorldStateKey` enum values.

The world state encoding must be mapped to and from the actual world i.e. the `GameState`.
- **Sensors** are responsible for mapping `GameState` into `WorldState`.
- **Operators** are responsible for mapping `WorldState` into `GameState`.

A **domain** is basically a declaration of all actions that the AI can take in the world.
It is typically a graph with a strongly hierarchical topology -- in some cases (such as an AI that does not need to reason far into the future), this topology can actually be a tree. 
The topology of the graph complicates when recursive actions are introduced, which are often useful for forming longer-term plans.

The **planner** is responsible for building a sequence of domain actions based on the encoded world state.
It is important to note that the planner simulates the effects of actions on the world state -- this is how the planner is able to resolve cyclic domain graphs.
Specifically, actions have predicate conditions.
When these predicate conditions are not met, the action cannot not be taken.
As the planner simulates effects, predicates for some actions that used to be satisfied may no longer be satisfied.


## Usage
This section will explain usage of the system by example.

The tests in [`domain.zig`](./domain.zig) provide good examples of how to use the tools provided here.
The first step is to declare a domain, which consists of **conditions**, **effects**, and **operators**.
**Conditions** are predicates that must be satisfied in order for an action to be taken.
**Effects** are what is expected to happen as a result of taking an action. They are used for planning purposes.
**Operators** are the actions themselves -- the functions that modify the `GameState`.

In the following examples, the term "task" is synonymous with "action".
Notice that there are **primitive** and **compound** tasks; compound tasks are composed of both primitive tasks and compound tasks.
Compound tasks enable recursion and serve as a notion of task abstraction.
```zig
fn alwaysReturnTrue(_: []const WorldStateValue) bool {
    return true;
}

fn effectSwitchTestWorldState(ws: []WorldStateValue) void {
    ws[@intFromEnum(WorldStateKey.WsTest)] = .TestSwitched;
}

fn operatorNoOp(
    entity: usize, 
    worldState: []WorldStateValue, 
    gameState: *game.GameState,
) TaskStatus {
    _ = entity;
    _ = worldState;
    _ = gameState;
    return .Succeeded;
}

const domain = DomainBuilder.init(std.testing.allocator)
    .task("task name", .PrimitiveTask)
        .condition("first condtion", alwaysReturnTrue)
        .condition("second condition", alwaysReturnTrue)
        .effect("first effect", effectSwitchTestWorldState)
        .operator("operator name", operatorNoOp)
    .end()

    .task("another task name", .PrimitiveTask)
        .condition("first condtion", alwaysReturnTrue)
        .condition("second condition", alwaysReturnTrue)
        .effect("first effect", effectSwitchTestWorldState)
        .operator("operator name", operatorNoOp)
    .end()

    .task("compound task name", .CompoundTask)
        .method("first method name")
            .condition("method condition", alwaysReturnTrue)
            .subtask("another task name")
            .subtask("task name")
        .end()
        .method("second method name")
            .condition("method condition", alwaysReturnTrue)
            // This compound task recursively references itself.
            .subtask("compound task name")
        .end()
    .end()

    .build();
defer domain.deinit();
```

The next step is to create a planner.
The planner requires a root task from the domain, which serves as the starting point for all plans.
This root task is a compound task in all nontrivial cases.
```zig
const rootTask = domain.getTaskByName("compound task name").?;
var planner = HtnPlanner.init(allocator, rootTask);
defer planner.deinit();
```

Plans can then be generated using this planner by passing in a world state.
Note that the `HtnPlanner` does not mutate `worldState` -- it makes a copy for internal use.
The caller is responsible for freeing generated plans.
```zig
var worldState = WorldState.init(allocator);
defer worldState.deinit();

var plan = planner.processTasks(&worldState).getPlan();
defer plan.deinit();
```


## System details
- Currently, each AI component is given its own planner and world state. In some AI systems where planning is much more expensive (e.g. GOAP), it would not be scalable for each AI to have its own planner. However, HTN planning is typically very cheap, making this simpler architecture more viable.
- `GameState`, `WorldStateKey`, and `WorldStateValue` types are used throughout this HTN implementation, which makes the planner implementation not immediately portable to other projects. However, the work needed is minimal -- just define your own `WorldStateKey` and `WorldStateValue` in [`worldstate.zig`](./worldstate.zig), and your own `GameState` in [`game.zig`](../game.zig).
- Sensors and task runners are highly specific to a given project, so I didn't try to implement them here in a generic way. Instead, they are implemented in [`src/ai.zig`](../ai.zig) and [`src/game.zig`](../game.zig). 
- There is currently no validation in `DomainBuilder`. You can easily make a domain that `HtnPlanner` will loop infinitely on. This is not only because domains can be cyclic graphs, but also because there is a temporal component to the structure of the graph. It is not straightforward to validate that a cycle will eventually break based on how `WorldState` changes over time. That is to say, it's easy to get yourself in a tricky to debug situation as you develop your domain.
