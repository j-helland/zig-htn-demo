const std = @import("std");
const IntegerBitSet = std.bit_set.IntegerBitSet;

pub const components = @import("components.zig");
pub const Queue = @import("game").Queue;

const LOGGER = std.log;
const MAX_COMPONENTS = 1024;
const MAX_COMPONENTS_PER_ENTITY = 32;

pub const ComponentSignature = IntegerBitSet(MAX_COMPONENTS_PER_ENTITY);
pub const ComponentType = usize;
pub const EntityType = usize;

pub fn EntityIdMap(comptime T: type) type {
    return std.AutoArrayHashMap(EntityType, T);
}

pub fn Ecs(comptime Types: anytype) type {
    return struct {
        const This = @This();

        entityManager: EntityManager,
        componentManager: ComponentManager(Types),
        signatureIndexMap: std.AutoArrayHashMap(ComponentType, usize),

        pub fn init(allocator: std.mem.Allocator) !This {
            var ecs = This{
                .entityManager = try EntityManager.init(allocator),
                .componentManager = try ComponentManager(Types).init(allocator),
                .signatureIndexMap = std.AutoArrayHashMap(ComponentType, usize).init(allocator),
            };

            // Map types to signature bitset indices.
            inline for (Types) |T, idx| {
                if (idx == MAX_COMPONENTS_PER_ENTITY) {
                    return error.MaxComponentsPerEntityExceeded;
                }
                try ecs.signatureIndexMap.put(typeid(T), idx);
            }

            return ecs;
        }

        pub fn deinit(self: *This) void {
            self.entityManager.deinit();
            self.componentManager.deinit();
            self.signatureIndexMap.deinit();
        }

        pub fn registerEntity(self: *This) !EntityType {
            return self.entityManager.registerEntity();
        }

        pub fn removeEntity(self: *This, entity: EntityType) void {
            self.componentManager.removeAll(entity);
            _ = self.entityManager.removeEntity(entity);
        }

        pub fn setComponent(self: *This, entity: EntityType, comptime T: type, component: T) !void {
            try self.componentManager.set(entity, T, component);
            // Cannot be null because otherwise error about unregistered would have already returned.
            const index = self.signatureIndexMap.get(typeid(T)).?;
            try self.entityManager.setSignature(entity, index);
        }

        pub fn hasComponent(self: *This, entity: EntityType, comptime T: type) bool {
            const sig = self.entityManager.getSignature(entity) orelse return false;
            const index = self.signatureIndexMap.get(typeid(T)) orelse return false;
            return sig.isSet(index);
        }

        pub fn removeComponent(self: *This, entity: EntityType, comptime T: type) !void {
            try self.componentManager.remove(entity, T);
            const index = self.signatureIndexMap.get(typeid(T)).?;
            try self.entityManager.unsetSignature(entity, index);
        }
    };
}

pub const EntityManager = struct {
    const This = @This();

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
        try self.entities.put(id, ComponentSignature.initEmpty());
        self.nextId += 1;
        return id;
    }

    pub fn getSignature(self: *EntityManager, entity: EntityType) ?ComponentSignature {
        return self.entities.get(entity) orelse return null;
    }

    pub fn setSignature(self: *EntityManager, entity: EntityType, index: usize) !void {
        var sig = self.getSignature(entity) orelse return error.NoSignatureForEntity;
        sig.set(index);
        try self.entities.put(entity, sig);
    }

    pub fn unsetSignature(self: *EntityManager, entity: EntityType, index: usize) !void {
        var sig = self.getSignature(entity) orelse return error.NoSignatureForEntity;
        sig.unset(index);
        try self.entities.put(entity, sig);
    }

    pub fn removeEntity(self: *EntityManager, id: EntityType) bool {
        return self.entities.swapRemove(id);
    }

    pub fn iterator(self: *EntityManager) EntityIdMap(ComponentSignature).Iterator {
        return self.entities.iterator();
    }
};

pub fn ComponentManager(comptime Types: anytype) type {
    return struct {
        /// Storage backend for component lists.
        const This = @This();
        const StorageType = ComponentFixedList;

        componentTypes: @TypeOf(Types) = Types,
        allocator: std.mem.Allocator,
        /// Values are pointers to StorageType values
        componentLists: std.AutoArrayHashMap(ComponentType, usize),

        pub fn init(allocator: std.mem.Allocator) !This {
            var manager = This{
                .allocator = allocator,
                .componentLists = std.AutoArrayHashMap(ComponentType, usize).init(allocator),
            };

            inline for (manager.componentTypes) |T| {
                const id = typeid(T);

                const list = try allocator.create(StorageType(T));
                list.* = try StorageType(T).init(allocator);
                try manager.componentLists.put(id, @ptrToInt(list));
            }

            return manager;
        }

        pub fn deinitComponent(self: *This, comptime T: type) void {
            const id = typeid(T);
            const listAddr = self.componentLists.get(id) orelse unreachable;
            const listPtr = @intToPtr(*StorageType(T), listAddr);
            listPtr.deinit();
            self.allocator.destroy(listPtr);
        }

        pub fn deinit(self: *This) void {
            inline for (self.componentTypes) |T| {
                const list = self.getComponentList(T) catch unreachable;
                list.deinit();
                self.allocator.destroy(list);
            }
            self.componentLists.deinit();
        }

        pub fn set(self: *This, entity: EntityType, comptime T: type, component: T) !void {
            var list = try self.getComponentList(T);
            try list.add(entity, component);
        }

        pub fn get(self: *This, entity: EntityType, comptime T: type) ?*T {
            var list = self.getComponentList(T) catch {
                std.log.err("Failed to get {any} component list for entity {d}", .{T, entity});
                @panic("Failed to get component list");
            };
            return list.get(entity);
        }

        /// Unsafe version of get. Will panic if the component is not registered. Use with caution.
        pub fn getKnown(self: *This, entity: EntityType, comptime T: type) *T {
            var list = self.getComponentList(T) catch unreachable;
            return list.get(entity).?;
        }

        pub fn remove(self: *This, entity: EntityType, comptime T: type) !void {
            var list = try self.getComponentList(T);
            try list.remove(entity);
        }

        pub fn removeAll(self: *This, entity: EntityType) void {
            inline for (self.componentTypes) |T| {
                const list = self.getComponentList(T) catch unreachable;
                list.remove(entity) catch {}; // We don't care if there are no components of this type for this entity.
            }
        }

        pub fn iterator(self: *This, comptime T: type) Iterator(StorageType(T), *T) {
            var list = self.getComponentList(T) catch return .{};
            return list.iterator();
        }

        fn getComponentList(self: *This, comptime T: type) !*StorageType(T) {
            const addr = self.componentLists.get(typeid(T)) orelse return error.ComponentTypeNotRegistered;
            return @intToPtr(*StorageType(T), addr);
        }
    };
}

pub fn ComponentFixedList(comptime T: type) type {
    return struct {
        const This = @This();

        components: [MAX_COMPONENTS]T,
        entityIndexMap: EntityIdMap(usize),
        freeList: Queue(usize),

        pub fn init(allocator: std.mem.Allocator) !This {
            var queue = Queue(usize).init(allocator);
            var idx: usize = 0;
            while (idx < MAX_COMPONENTS) : (idx += 1) {
                try queue.push(idx);
            }

            return .{
                .components = .{},
                .entityIndexMap = EntityIdMap(usize).init(allocator),
                .freeList = queue,
            };
        }

        pub fn deinit(self: *This) void {
            // If components have a `fn deinit(...)` declaration, we need to call it.
            for (self.entityIndexMap.keys()) |entity| {
                var component = self.get(entity) orelse continue;
                self.deinitComponent(component);
            }

            self.entityIndexMap.deinit();
            self.freeList.deinit();
        }

        pub fn add(self: *This, entity: EntityType, component: T) !void {
            const idx = self.freeList.peek() orelse return error.SizeExceeded;

            const result = try self.entityIndexMap.getOrPutValue(entity, idx);
            if (result.found_existing) {
                std.log.err("Component type {} already set for entity {d}", .{T, entity});
                return error.ComponentAlreadySet;
            }
            self.components[idx] = component;
            _ = self.freeList.pop();
        }

        pub fn get(self: *This, entity: EntityType) ?*T {
            const idx = self.entityIndexMap.get(entity) orelse return null;
            return &self.components[idx];
        }

        pub fn remove(self: *This, entity: EntityType) !void {
            const idx = self.entityIndexMap.get(entity) orelse return error.NoSuchElement;
            _ = self.entityIndexMap.swapRemove(entity);
            self.deinitComponent(&self.components[idx]);
            try self.freeList.push(idx);
        }

        pub fn iterator(self: *This) Iterator(This, *T) {
            return .{ .parent = self };
        }

        pub fn size(self: *const This) usize {
            return MAX_COMPONENTS - self.freeList.len;
        }

        fn deinitComponent(self: *This, component: *T) void {
            _ = self;
            if (@hasDecl(T, "deinit")) component.deinit();
        }
    };
}

fn Iterator(comptime ParentType: type, comptime ValType: type) type {
    return struct {
        const This = @This();

        parent: ?*ParentType = null,
        idx: usize = 0,

        pub fn next(self: *This) ?ValType {
            if (self.parent == null or self.idx >= self.parent.?.size()) return null;
            defer self.idx += 1;
            return &self.parent.?.components[self.idx];
        }

        pub fn reset(self: *This) void {
            self.idx = 0;
        }
    };
}

fn typeid(comptime T: type) ComponentType {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return @ptrToInt(&H.byte);
}

const expect = std.testing.expect;

test "ComponentFixedList" {
    const TestComponent = struct {};
    const entity = 0;

    var list = try ComponentFixedList(TestComponent).init(std.testing.allocator);
    defer list.deinit();

    var component = TestComponent{};
    try list.add(entity, component);

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

test "component manager instantiation with types" {
    const TestComponent1 = struct {};
    const TestComponent2 = struct {};

    var c = try ComponentManager(.{ TestComponent1, TestComponent2 }).init(std.testing.allocator);
    defer c.deinit();

    const list1 = try c.getComponentList(TestComponent1);
    const list2 = try c.getComponentList(TestComponent2);
    try expect(list1.size() == 0);
    try expect(list2.size() == 0);

    try c.set(0, TestComponent1, .{});
    try expect(list1.size() == 1);
    try expect(list2.size() == 0);

    try c.set(0, TestComponent2, .{});
    try expect(list1.size() == 1);
    try expect(list2.size() == 1);

    c.removeAll(0);
    try expect(list1.size() == 0);
    try expect(list2.size() == 0);
}

test "remove component from entity" {
    const TestComponent = struct {};
    var ecs = try Ecs(.{TestComponent}).init(std.testing.allocator);
    defer ecs.deinit();

    const entity = try ecs.registerEntity();
    try ecs.setComponent(entity, TestComponent, .{});
    try expect(ecs.hasComponent(entity, TestComponent));

    try ecs.removeComponent(entity, TestComponent);
    try expect(!ecs.hasComponent(entity, TestComponent));
}

test "iterate components" {
    const T = struct {};
    var ecs = try Ecs(.{T}).init(std.testing.allocator);
    defer ecs.deinit();

    var it = ecs.componentManager.iterator(T);
    var count: usize = 0;
    while (it.next()) |_| : (count += 1) {}
    try expect(count == 0);

    const e1 = try ecs.registerEntity();
    try ecs.setComponent(e1, T, .{});
    const e2 = try ecs.registerEntity();
    try ecs.setComponent(e2, T, .{});
    const e3 = try ecs.registerEntity();
    try ecs.setComponent(e3, T, .{});

    it.reset();
    while (it.next()) |_| : (count += 1) {}
    try expect(count == 3);

    ecs.removeEntity(e2);

    count = 0;
    it.reset();
    while (it.next()) |_| : (count += 1) {}
    try expect(count == 2);
}

test "test Ecs instantiation" {
    const TestComponent = struct {};

    var ecs = try Ecs(.{TestComponent}).init(std.testing.allocator);
    defer ecs.deinit();
}
