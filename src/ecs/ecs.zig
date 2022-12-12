const std = @import("std");
const IntegerBitSet = std.bit_set.IntegerBitSet;

pub const components = @import("components/components.zig");

const LOGGER = std.log;
const MAX_COMPONENTS = 1024;
const MAX_COMPONENTS_PER_ENTITY = 32;

pub const ComponentSignature = IntegerBitSet(MAX_COMPONENTS_PER_ENTITY);
pub const ComponentType = usize;
pub const EntityType = usize;

pub fn EntityIdMap(comptime T: type) type {
    return std.AutoArrayHashMap(EntityType, T);
}

pub fn typeid(comptime T: type) ComponentType {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return @ptrToInt(&H.byte);
}

pub const Ecs = struct {
    entityManager: EntityManager,
    componentManager: ComponentManager,
    signatureIndexMap: std.AutoArrayHashMap(ComponentType, usize),
    signatureNextIndex: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Ecs {
        return .{
            .entityManager = try EntityManager.init(allocator),
            .componentManager = try ComponentManager.init(allocator),
            .signatureIndexMap = std.AutoArrayHashMap(ComponentType, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Ecs) void {
        self.entityManager.deinit();
        self.componentManager.deinit();
        self.signatureIndexMap.deinit();
    }

    pub fn registerEntity(self: *Ecs) !EntityType {
        return self.entityManager.registerEntity();
    }

    pub fn registerComponent(self: *Ecs, comptime T: type) !void {
        if (self.signatureNextIndex == MAX_COMPONENTS_PER_ENTITY) return error.TooManyComponents;
        try self.componentManager.registerComponent(T);
        try self.signatureIndexMap.put(typeid(T), self.signatureNextIndex);
        self.signatureNextIndex += 1;
    }

    pub fn setComponent(self: *Ecs, entity: EntityType, comptime T: type, component: T) !void {
        try self.componentManager.set(entity, T, component);
        // Cannot be null because otherwise error about unregistered would have already returned.
        const index = self.signatureIndexMap.get(typeid(T)).?;
        try self.entityManager.setSignature(entity, index);
    }

    pub fn hasComponent(self: *Ecs, entity: EntityType, comptime T: type) bool {
        const sig = self.entityManager.getSignature(entity) orelse return false;
        const index = self.signatureIndexMap.get(typeid(T)) orelse return false;
        return sig.isSet(index);
    }
};

pub const EntityManager = struct {
    const This = @This();

    // pub const EntityIterator = struct {
    //     parent: *const This,
    //     idx: usize = 0,

    //     pub fn next(self: *EntityIterator) EntityType {
    //         self.parent.entities.iterator()
    //     }
    // };

    entities: EntityIdMap(ComponentSignature),
    nextId: EntityType = 0,

    pub fn init(allocator: std.mem.Allocator) !EntityManager {
        return EntityManager{
            .entities = EntityIdMap(ComponentSignature).init(allocator),
        };
    }

    pub fn deinit(self: *EntityManager) void {
        self.entities.deinit();
    }

    pub fn registerEntity(self: *EntityManager) !EntityType {
        const id = self.nextId;
        try self.entities.put(id, IntegerBitSet(MAX_COMPONENTS_PER_ENTITY).initEmpty());
        self.nextId += 1;
        return id;
    }

    pub fn getSignature(self: *EntityManager, entity: EntityType) ?ComponentSignature {
        return self.entities.get(entity) orelse return null;
    }

    pub fn setSignature(self: *EntityManager, entity: EntityType, index: usize) !void {
        var sig = self.getSignature(entity)
            orelse return error.NoSignatureForEntity;
        sig.set(index);
        try self.entities.put(entity, sig);
    }

    pub fn removeEntity(self: *EntityManager, id: EntityType) bool {
        return self.entities.swapRemove(id);
    }

    pub fn iterator(self: *EntityManager) EntityIdMap(ComponentSignature).Iterator {
        return self.entities.iterator();
    }
};

// pub fn ComponentList(comptime T: type) type {
//     return struct {
//         const This = @This();

//         components: std.ArrayList(*T),
//         entityIndexMap: std.AutoArrayHashMap(EntityType, usize),

//         pub fn init(allocator: std.mem.Allocator) This {
//             return .{
//                 .components = std.ArrayList(*T).init(allocator),
//                 .entityIndexMap = std.AutoArrayHashMap(EntityType, usize).init(allocator),
//             };
//         }

//         pub fn deinit(self: *This) void {
//             self.components.deinit();
//             self.entityIndexMap.deinit();
//         }

//         pub fn addOrSet(self: *This, entity: EntityType, component: *T) !void {
//             const result = try self.entityIndexMap.getOrPutValue(entity, self.components.items.len);
//             if (result.found_existing) return;
//             try self.components.append(component);
//         }

//         pub fn get(self: *This, entity: EntityType) ?*T {
//             const idx = self.entityIndexMap.get(entity) orelse return null;
//             return self.components.items[idx];
//         }

//         pub fn iterator(self: *This) Iterator(This, *T) {
//             return .{ .parent = self };
//         }

//         pub fn size(self: *const This) usize {
//             return self.components.items.len;
//         }
//     };
// }

pub fn ComponentFixedList(comptime T: type) type {
    return struct {
        const This = @This();

        components: [MAX_COMPONENTS]T,
        entityIndexMap: std.AutoArrayHashMap(EntityType, usize),
        freeList: Queue(usize),

        pub fn init(allocator: std.mem.Allocator) !This {
            var queue = Queue(usize).init(allocator);
            var idx: usize = 0;
            while (idx < MAX_COMPONENTS) : (idx += 1) {
                try queue.push(idx);
            }

            return .{
                .components = .{},
                .entityIndexMap = std.AutoArrayHashMap(EntityType, usize).init(allocator),
                .freeList = queue,
            };
        }

        pub fn deinit(self: *This) void {
            self.entityIndexMap.deinit();
            self.freeList.deinit();
        }

        pub fn addOrSet(self: *This, entity: EntityType, component: T) !void {
            const idx = self.freeList.pop() orelse return error.SizeExceeded;

            const result = try self.entityIndexMap.getOrPutValue(entity, idx);
            if (result.found_existing) return;
            self.components[idx] = component;
        }

        pub fn get(self: *This, entity: EntityType) ?*T {
            const idx = self.entityIndexMap.get(entity) orelse return null;
            return &self.components[idx];
        }

        pub fn remove(self: *This, entity: EntityType) !void {
            const idx = self.entityIndexMap.get(entity) orelse return error.NoSuchElement;
            _ = self.entityIndexMap.swapRemove(entity);
            try self.freeList.push(idx);
        }

        pub fn iterator(self: *This) Iterator(This, *T) {
            return .{ .parent = self };
        }

        pub fn size(self: *const This) usize {
            return MAX_COMPONENTS - self.freeList.len;
        }
    };
}

pub const ComponentManager = struct {
    /// Storage backend for component lists.
    const StorageType = ComponentFixedList;

    allocator: std.mem.Allocator,
    componentTypes: std.AutoArrayHashMap(ComponentType, bool),
    /// Values are pointers to StorageType values
    componentLists: std.AutoArrayHashMap(ComponentType, usize),

    pub fn init(allocator: std.mem.Allocator) !ComponentManager {
        return ComponentManager{
            .allocator = allocator,
            .componentTypes = std.AutoArrayHashMap(ComponentType, bool).init(allocator),
            .componentLists = std.AutoArrayHashMap(ComponentType, usize).init(allocator),
        };
    }

    pub fn deinitComponent(self: *ComponentManager, comptime T: type) void {
        const id = typeid(T);
        const listAddr = self.componentLists.get(id) orelse unreachable;
        const listPtr = @intToPtr(*StorageType(T), listAddr);
        listPtr.deinit();
        self.allocator.destroy(listPtr);
    }

    pub fn deinit(self: *ComponentManager) void {
        self.componentLists.deinit();
        self.componentTypes.deinit();
    }

    pub fn registerComponent(self: *ComponentManager, comptime T: type) !void {
        if (self.isRegistered(T)) return error.ComponentTypeAlreadyRegistered;

        const id = typeid(T);
        try self.componentTypes.put(id, true);

        const list = try self.allocator.create(StorageType(T));
        list.* = try StorageType(T).init(self.allocator);
        try self.componentLists.put(id, @ptrToInt(list));
    }

    pub fn set(self: *ComponentManager, entity: EntityType, comptime T: type, component: T) !void {
        var list = try self.getComponentList(T);
        try list.addOrSet(entity, component);
    }

    pub fn get(self: *ComponentManager, entity: EntityType, comptime T: type) !?*T {
        var list = try self.getComponentList(T);
        return list.get(entity);
    }

    /// Unsafe version of get. Will panic if the component is not registered. Use with caution.
    pub fn getKnown(self: *ComponentManager, entity: EntityType, comptime T: type) *T {
        var list = self.getComponentList(T) catch unreachable;
        return list.get(entity).?;
    }

    pub fn remove(self: *ComponentManager, entity: EntityType, comptime T: type) !void {
        var list = try self.getComponentList(T);
        try list.remove(entity);
    }

    pub fn iterator(self: *ComponentManager, comptime T: type) !Iterator(StorageType(T), *T) {
        return .{ .parent = try self.getComponentList(T) };
    }

    fn isRegistered(self: *ComponentManager, comptime T: type) bool {
        return self.componentTypes.contains(typeid(T));
    }

    fn getComponentList(self: *ComponentManager, comptime T: type) !*StorageType(T) {
        if (!self.isRegistered(T)) return error.ComponentTypeNotRegistered;
        const addr = self.componentLists.get(typeid(T)).?;
        return @intToPtr(*StorageType(T), addr);
    }
};

// pub fn SystemList(comptime T: type) type {
//     return struct {
//         const This = @This();

//         systems: std.ArrayList(T),

//         pub fn init(allocator: std.mem.Allocator) This {
//             return This{
//                 .systems = std.ArrayList(T).init(allocator),
//             };
//         }

//         pub fn deinit(self: *This) void {
//             self.systems.deinit();
//         }
//     };
// }

// pub const SystemManager = struct {
//     allocator: std.mem.Allocator,

// };

pub fn Iterator(comptime ParentType: type, comptime ValType: type) type {
    return struct {
        const This = @This();

        parent: *ParentType,
        idx: usize = 0,

        pub fn next(self: *This) ?ValType {
            if (self.idx >= self.parent.size()) return null;
            defer self.idx += 1;
            return &self.parent.components[self.idx];
        }

        pub fn reset(self: *This) void {
            self.idx = 0;
        }
    };
}

pub fn Queue(comptime Child: type) type {
    return struct {
        const This = @This();
        const Node = struct {
            data: Child,
            next: ?*Node,
        };
        gpa: std.mem.Allocator,
        start: ?*Node,
        end: ?*Node,
        len: usize = 0,

        pub fn init(gpa: std.mem.Allocator) This {
            return This{
                .gpa = gpa,
                .start = null,
                .end = null,
            };
        }

        pub fn deinit(self: *This) void {
            while (self.pop()) |_| {}
        }

        pub fn push(this: *This, value: Child) !void {
            defer this.len += 1;
            const node = try this.gpa.create(Node);
            node.* = .{ .data = value, .next = null };
            if (this.end) |end| end.next = node //
            else this.start = node;
            this.end = node;
        }

        pub fn pop(this: *This) ?Child {
            const start = this.start orelse return null;
            defer this.len -= 1;
            defer this.gpa.destroy(start);
            if (start.next) |next|
                this.start = next
            else {
                this.start = null;
                this.end = null;
            }
            return start.data;
        }
    };
}


const expect = std.testing.expect;

test "test ComponentFixedList" {
    const TestComponent = struct {};
    const entity = 0;

    var list = try ComponentFixedList(TestComponent).init(std.testing.allocator);
    defer list.deinit();

    var component = TestComponent{};
    try list.addOrSet(entity, component);

    // Ensure access by entity id retrieves component.
    try expect(list.size() == 1);
    try expect(list.entityIndexMap.contains(entity));
    try expect(std.meta.eql(component, list.get(entity).?.*));

    // Ensure access by iterator retrieves component.
    var it = list.iterator();
    var count: usize = 0;
    while (it.next()) |val| : (count += 1) {
        try expect(std.meta.eql(component, val.*));
    }
    // Ensure iterator respects list size.
    try expect(count == 1);

    // Ensure removed elements are not accessible.
    try list.remove(entity);
    try expect(list.size() == 0);
    it.reset();
    try expect(it.next() == null);
}
