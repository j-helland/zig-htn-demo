# ECS
This ECS implementation is generic thanks to extensive use of Zig `comptime`.
Component types can only be registered when an ecs is created.
For example,
```zig
const Type1 = struct { field1: i32 };
const Type2 = struct { pub fn deinit(self: *Type2) void {} };
const ComponentTypes = .{ Type1, Type2 };
var ecs = Ecs(ComponentTypes).init(allocator);
defer ecs.deinit();
```

These component types can be any struct.
If the struct has a `deinit` method, this will be called automatically by `Ecs.deinit`. 
This means that any cleanup required by instances of a component type must handle all of this in their `deinit` method.

Only one component of each type can be added to any given entity.
For example,
```zig
const entity = try ecs.registerEntity();
try state.ecs.setComponent(entity, Type1, .{ .field1 = 0 });
```
Trying to add another `Type1` component will return an error.

Retrieving components from an entity is straightforward:
```zig
var component = ecs.componentManager.get(entity, Type1) orelse {
    std.log.err("Could not get component", .{});
    return error.CouldNotGetComponent;
};
```

Components can be iterated over:
```zig
var it = ecs.componentManager.iterator(Type1);
while (it.next()) |component| {
    // Do stuff
}
```

Entities can also be iterated over:
```zig
var it = ecs.entityManager.iterator();
while (it.next()) |keyVal| {
    const entity = keyVal.key_ptr.*;
    const signature = keyVal.value_ptr.*;

    if (ecs.hasComponent(entity, Type1)) {
        // Do stuff
    }
}
```

# System Details
- Components for entities are stored in fixed lists for cache locality purposes. A hash table maps entities to their components in these lists, making it quick to access a given entities specific components.
    - A freelist is used to mark free blocks in the fixed component list.
- Each entity is given a signature -- a bitset where each component type maps to a bitset index. This makes it fast to check if an entity has a certain component.