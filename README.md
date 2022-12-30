# Hierarchical Task Network (HTN) AI Demo
This is a demo of a Hierarchical Task Network (HTN) AI implementation in Zig.
The only dependency is SDL2.

My goals with this project were:
- To learn Zig.
- To learn about HTNs.
- To have as much fun as possible.

The project has a couple of features that I think are neat:
- [HTN implementation](./src/htn/) that makes defining domains straightforward.
- A flexible [Entity Component System (ECS) implementation](./src/ecs/).
- Easy cross-compilation thanks to Zig.


## Video demos (clickable images)
Check out the core AI behaviors in the videos below (click on an image to open a youtube video).

### Flanking behavior

[<img src=https://img.youtube.com/vi/8vVUdJZckKI/0.jpg width="200"/>](https://youtu.be/8vVUdJZckKI)

When navigating to the player, the AI will try to flank the player. 
This behavior is implemented using A* routing with a distance metric biased away from the player's line of sight.

The visibility bias is intuitively very simple: consider visible locations further away by a constant factor.
This approach works fairly well to avoid moving into player view when near the player while smoothly transitioning to normal movement far away from the player.

When the AI spots the player, it records a snapshot of the player's view, finds a nearby hiding place, and then routes to the player using A* with respect to the snapshot of the player's view.

### Searching behavior
[<img src=https://img.youtube.com/vi/tNm8sTDeY2o/0.jpg width="200"/>](https://youtu.be/tNm8sTDeY2o)

The AI will default to searching for the player when
1. The player hasn't been spotted yet.
2. The AI has lost track of the player.

More details on the second case: when the AI spots the player, it will hide and then navigate to the last known player location for an attack.
This can fail when the player has moved behind cover while out of the enemy's line of sight.
This is what is meant by losing track of the player.


## Running the demo
*NOTE: this project has only been tested on macOS Monetery 12.4 with an M1 chip. While other platforms / architectures have not been tested, any changes to [`build.zig`](./build.zig) should be minimal.*

### **INSTALLATION**
You need to install the following dependencies before building:
- `SDL2`
- `SDL2_Image`

On macOS, you can install these via `brew install sdl2 sdl2_image`.

Then, 
- `git clone https://github.com/j-helland/zig-htn-demo.git`
- `cd zig-htn-demo`
- `zig build run`

This should launch the program automatically.

### **CONTROLS**
- Move using `WASD`
- Quit using `Esc`
- Right-click to spawn a wall at the mouse position.
- `Spacebar` to spawn an enemy at the mouse position.
- Use the mouse to control the line-of-sight.


## Project Organization
- [`src/game.zig`](./src/game.zig) contains the core game loop and `GameState` definition. Additionally:
    - ECS systems are defined here e.g. `handlePlayer`
    - The HTN planner is defined here as an ECS system `handleEnemyAI`.
- [`src/ai.zig`](./src/ai.zig) Defined the HTN domain, as well as the conditions, operators, and sensors needed by the HTN planner to run the AI.
- [`src/htn/`](./src/htn/) Contains the HTN planner, domain builder, and world state definition. Currently, the world state is specialized to this demo, meaning that this HTN implementation requires a small amount of work to be used in other projects.
- [`src/ecs/ecs.zig`](./src/ecs/ecs.zig) Contains a generic ECS implementation. It is not currently optimized.
