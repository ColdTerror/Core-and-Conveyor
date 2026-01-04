# Core and Conveyor
City Builder TD: Rise to Ruin + Mindustry

City Builder TD Brainstorm: Rise to Ruin + Mindustry
Core Concept

A hybrid survival city builder and automation tower defense where the game transitions from manual villager labor to high-scale industrial supply lines.

1. Game Phases

• The Village Era (Manual): Focus on survival, housing, and basic gathering. Villagers carry resources in baskets. Defense is manned by bowmen.

• The Industrial Era (Automation): Production outpaces human speed. Players build conveyor belts, pipes, and factories.

• The Vanguard Era (Expansion): Villagers "level up" into elite roles (Research, Maintenance, or Combat) to recapture territory using gear produced by the factories.

2. Logistics & Production

• Physical Logistics: Resources must be moved via belts. Advanced ammo is too heavy for villagers to carry.

• Maintenance Corps: Automated buildings degrade over time; trained villagers act as technicians to keep the line running.

• The "Loader" Station: A bridge between eras where villagers manually feed items onto the start of an automated belt.

3. Combat & Defense

• The Sieve (Maze): Strategic pathing to slow enemies.

• The Kill Box (Death Zone): Elemental synergies (e.g., Oil + Fire, Rain + Tesla).

• Anti-Air: Net Guns to ground flyers, forcing them into ground-based death zones.

• Annoying Enemies: Gremlins (jam belts), Sappers (target power lines), and Magnetars (steal items off belts).

4. Next Steps for a Godot Beginner

1. Grid System: Implement a basic `TileMap` or `GridMap` to handle building placement and pathfinding.

2. Resource Class: Create a custom Resource script to define different items (Wood, Stone, Iron).

3. Villager AI: Use a simple Finite State Machine (FSM) for "Gather -> Carry -> Build" logic.

4. The Belt System: Prototype a simple "Conveyor" that moves a Sprite from Point A to Point B.

5. Tower Targeting: Learn `Area2D` and `look_at()` for basic turret logic.
---

7. Campaign Mode: "Sector Evolution"

• Global Map: Divided into sectors (Mindustry style) with varying resources and threat levels.

• The Launch Cycle:

  1. Landing: Start with a few "Pioneer" villagers and basic supplies.

  2. Domination: Build up the industry to secure the sector.

  3. Export: Once secure, build a "Launch Pad" to send resources to the global pool or the next sector.

• Persistent Progress: Technology stays unlocked, but physical infrastructure is rebuilt each map to master the "Evolution Loop."


