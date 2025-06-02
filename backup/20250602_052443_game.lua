pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- sokoban_pcg.p8

-- constants
W = 16        -- total width including border
H = 16        -- total height including border

TILE_WALL  = 1
TILE_FLOOR = 0
TILE_GOAL  = 2

-- game states
GAME_STATE_MENU     = 0
GAME_STATE_PLAY     = 1
GAME_STATE_GAMEOVER = 2

-- global state
game_state       = GAME_STATE_MENU
level_number     = 1      -- current level index (starts at 1)
base_push_count  = 3      -- starting ヌ█うperfect pushesヌ█え for level 1
slack_initial    = 5      -- initial extra pushes beyond perfect (decreases each level)
map              = {}     -- map[y][x] array
box_x, box_y     = 0, 0
player_x, player_y = 0, 0
goal_x, goal_y   = 0, 0
perfect_pushes   = 0      -- known minimum pushes for current puzzle
remaining_pushes = 0      -- how many pushes the player still has

-- ============================================================================
-- 1) MAP INITIALIZATION AND OBSTACLE GENERATION
-- ============================================================================

function init_map()
  -- create an empty map: border walls + interior floors
  for y = 1, H do
    map[y] = {}
    for x = 1, W do
      if x == 1 or x == W or y == 1 or y == H then
        map[y][x] = TILE_WALL
      else
        map[y][x] = TILE_FLOOR
      end
    end
  end

  -- sprinkle interior obstacles (random walls) based on level_number
  -- obstacle probability grows with level_number (max 20%)
  local p = min(0.20, 0.02 * level_number)
  for y = 2, H - 1 do
    for x = 2, W - 1 do
      -- leave the very first generation empty: we'll choose goal & box later
      if rnd() < p then
        map[y][x] = TILE_WALL
      end
    end
  end
end

-- pick a random interior floor tile (not a wall)
function choose_random_floor()
  local fx, fy
  repeat
    fx = flr(rnd(W - 2)) + 2
    fy = flr(rnd(H - 2)) + 2
  until map[fy][fx] == TILE_FLOOR
  return fx, fy
end

-- from (gx, gy), pick a random adjacent floor tile for the player
function choose_adjacent_floor(gx, gy)
  local dirs = {
    {1, 0},
    {-1, 0},
    {0, 1},
    {0, -1},
  }
  -- shuffle directions
  local shuffled = {}
  for i = 1, #dirs do
    shuffled[i] = dirs[i]
  end
  for i = #shuffled, 2, -1 do
    local j = flr(rnd(i)) + 1
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end

  for _, d in ipairs(shuffled) do
    local px, py = gx + d[1], gy + d[2]
    if map[py][px] == TILE_FLOOR then
      return px, py
    end
  end

  -- fallback (very rare): pick any adjacent floor if shuffle failed
  for _, d in ipairs(dirs) do
    local px, py = gx + d[1], gy + d[2]
    if map[py][px] == TILE_FLOOR then
      return px, py
    end
  end

  -- if no adjacent floor (extremely unlikely if map isnヌ█▥t full of walls):
  return gx + 1, gy
end

-- check if (x,y) is inside bounds and is FLOOR or GOAL
function is_floor(x, y)
  return
    x >= 1
    and x <= W
    and y >= 1
    and y <= H
    and (map[y][x] == TILE_FLOOR or map[y][x] == TILE_GOAL)
end

-- simple integer random in [a..b]
function rnd_int(a, b)
  return flr(rnd(b - a + 1)) + a
end

-- ============================================================================
-- 2) PUZZLE GENERATION VIA REVERSE PUSH + BFS VALIDATION
-- ============================================================================

function generate_puzzle(N)
  --
  -- 1) Rebuild map (border + interior obstacles)
  --
  init_map()

  --
  -- 2) Place a goal on a random floor tile
  --
  goal_x, goal_y = choose_random_floor()
  map[goal_y][goal_x] = TILE_GOAL

  --
  -- 3) Start with box on goal, choose player adjacent
  --
  box_x, box_y = goal_x, goal_y
  player_x, player_y = choose_adjacent_floor(goal_x, goal_y)

  --
  -- 4) Perform exactly N ヌ█うreverse pushesヌ█え to guarantee a known solution length of N
  --
  local count = 0
  while count < N do
    local valid_dirs = {}

    -- check each cardinal direction d = (dx,dy)
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local dx, dy = d[1], d[2]

      -- required ヌ█うforward pushヌ█え scenario: player would stand at (bx - dx, by - dy)
      -- and the box would come from (bx + dx, by + dy)
      local px_cand = box_x - dx
      local py_cand = box_y - dy
      local bx_cand = box_x + dx
      local by_cand = box_y + dy

      if
        is_floor(px_cand, py_cand)
        and is_floor(bx_cand, by_cand)
      then
        -- this direction is a valid reverse push
        add(valid_dirs, {dx, dy})
      end
    end

    if #valid_dirs == 0 then
      -- no valid reverse push found ヌ●★ restart whole generation
      return generate_puzzle(N)
    end

    -- pick one direction at random
    local idx = rnd_int(1, #valid_dirs)
    local dx, dy = valid_dirs[idx][1], valid_dirs[idx][2]

    -- perform the ヌ█うreverse pushヌ█え: move box one tile opposite to (dx,dy),
    -- and put the player where the box was previously
    local new_bx = box_x - dx
    local new_by = box_y - dy
    local new_px = box_x
    local new_py = box_y

    box_x, box_y       = new_bx, new_by
    player_x, player_y = new_px, new_py

    count += 1
  end

  --
  -- 5) We now know ヌ█うperfect_pushes = N.ヌ█え Validate by running a BFSヌ█…based solver.
  --
  perfect_pushes = N
  local found = compute_min_pushes(player_x, player_y, box_x, box_y, goal_x, goal_y)
  if found == nil or found != N then
    -- if BFS did not return exactly N, generation was invalid ヌ●★ retry
    return generate_puzzle(N)
  end

  --
  -- 6) Compute ヌ█うslackヌ█え based on level_number and set remaining_pushes
  --
  local slack = max(0, slack_initial - (level_number - 1))
  remaining_pushes = perfect_pushes + slack
end

-- BFS helper: can the player travel from (sx,sy) to (tx,ty) if (bx_block,by_block) is treated as an obstacle?
function can_player_reach(sx, sy, tx, ty, bx_block, by_block)
  local vis = {}
  for y = 1, H do
    vis[y] = {}
    for x = 1, W do
      vis[y][x] = false
    end
  end

  local q = {}
  add(q, {sx, sy})
  vis[sy][sx] = true

  while #q > 0 do
    local st = deli(q)
    local px, py = st[1], st[2]
    if px == tx and py == ty then
      return true
    end
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local nx, ny = px + d[1], py + d[2]
      if
        nx >= 1
        and nx <= W
        and ny >= 1
        and ny <= H
        and not vis[ny][nx]
        and map[ny][nx] != TILE_WALL
        and not (nx == bx_block and ny == by_block)
      then
        vis[ny][nx] = true
        add(q, {nx, ny})
      end
    end
  end

  return false
end

-- BFS over (player, box) states to compute minimal pushes to get boxヌ●★(gx,gy)
function compute_min_pushes(sx, sy, bx, by, gx, gy)
  -- 4D visited array: visited[py][px][by][bx]
  local visited = {}
  for py = 1, H do
    visited[py] = {}
    for px = 1, W do
      visited[py][px] = {}
      for by2 = 1, H do
        visited[py][px][by2] = {}
        for bx2 = 1, W do
          visited[py][px][by2][bx2] = false
        end
      end
    end
  end

  local q = {}
  add(q, {sx, sy, bx, by, 0})
  visited[sy][sx][by][bx] = true

  while #q > 0 do
    local st = deli(q)
    local px, py, cur_bx, cur_by, pushes = st[1], st[2], st[3], st[4], st[5]

    -- if the box is already on the goal, we have the minimal push count
    if cur_bx == gx and cur_by == gy then
      return pushes
    end

    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local dx, dy = d[1], d[2]
      local req_px = cur_bx - dx
      local req_py = cur_by - dy
      local new_bx = cur_bx + dx
      local new_by = cur_by + dy

      -- must have req_px,req_py as a floor tile (to stand and push)
      if not is_floor(req_px, req_py) then
        goto dir_done
      end
      -- target new box location must also be a floor/goal
      if not is_floor(new_bx, new_by) then
        goto dir_done
      end
      -- can the player reach req_px,req_py (without stepping on the box itself)
      if not can_player_reach(px, py, req_px, req_py, cur_bx, cur_by) then
        goto dir_done
      end

      -- after a successful push, the player stands where the box was
      local new_px, new_py = cur_bx, cur_by
      if not visited[new_py][new_px][new_by][new_bx] then
        visited[new_py][new_px][new_by][new_bx] = true
        add(q, {new_px, new_py, new_bx, new_by, pushes + 1})
      end

      ::dir_done::
    end
  end

  return nil
end

-- ============================================================================
-- 3) INPUT HANDLING AND GAMEヌ█…STATE TRANSITIONS
-- ============================================================================

function _update()
  if game_state == GAME_STATE_MENU then
    -- In the main menu, wait for ❎ (button 5) to start
    if btnp(5) then
      level_number = 1
      local N = base_push_count + (level_number - 1)
      generate_puzzle(N)
      game_state = GAME_STATE_PLAY
    end

  elseif game_state == GAME_STATE_PLAY then
    -- Inヌ█…game movement only when ヌ█うPLAYヌ█え state
    if btnp(0) then try_move(-1, 0) end   -- ヌえな left
    if btnp(1) then try_move(1, 0) end    -- ヌえに right
    if btnp(2) then try_move(0, -1) end   -- ヌ∧の up
    if btnp(3) then try_move(0, 1) end    -- ヌ∧も down

  elseif game_state == GAME_STATE_GAMEOVER then
    -- On Game Over, press ❎ to return to Main Menu
    if btnp(5) then
      game_state = GAME_STATE_MENU
    end
  end
end

-- attempt a player move or push
function try_move(dx, dy)
  local tx = player_x + dx
  local ty = player_y + dy

  -- if next tile is a wall, do nothing
  if map[ty][tx] == TILE_WALL then
    return
  end

  -- if next tile is the box, attempt to push
  if tx == box_x and ty == box_y then
    local nbx, nby = box_x + dx, box_y + dy
    if not is_floor(nbx, nby) then
      -- cannot push into a wall or outside
      return
    end
    -- valid push: move the box + move the player
    box_x, box_y       = nbx, nby
    player_x, player_y = tx, ty
    remaining_pushes -= 1

    check_end_conditions()
  else
    -- normal walk (no push)
    player_x, player_y = tx, ty
  end
end

-- check for win (boxヌ●★goal) or loss (no pushes left)
function check_end_conditions()
  if box_x == goal_x and box_y == goal_y then
    -- level complete ヌ●★ bump level_number and generate next puzzle
    level_number += 1
    local N = base_push_count + (level_number - 1)
    generate_puzzle(N)
  elseif remaining_pushes < 0 then
    -- out of pushes ヌ●★ Game Over
    game_state = GAME_STATE_GAMEOVER
  end
end

-- ============================================================================
-- 4) DRAWING EACH GAME STATE
-- ============================================================================

function _draw()
  cls()

  if game_state == GAME_STATE_MENU then
    -- Main Menu Screen
    rectfill(0, 0, 127, 127, 0)       -- black background
    print_centered("SOKOBAN PCG",  40, 7)
    print_centered("A Procedural Puzzle", 52, 6)
    print_centered("Press ❎ to Start",  80, 7)

  elseif game_state == GAME_STATE_PLAY then
    -- Draw the map tiles
    for y = 1, H do
      for x = 1, W do
        local t = map[y][x]
        local sx = (x - 1) * 8
        local sy = (y - 1) * 8
        if t == TILE_WALL then
          rectfill(sx, sy, sx + 7, sy + 7, 5)   -- dark gray walls
        elseif t == TILE_GOAL then
          -- a hollow box to mark the goal
          rect(sx, sy, sx + 7, sy + 7, 11)     -- light blue goal outline
        else
          rectfill(sx, sy, sx + 7, sy + 7, 0)   -- floor = black
        end
      end
    end

    -- Draw the box (filled circle) at (box_x, box_y)
    local bx_draw = (box_x - 1) * 8
    local by_draw = (box_y - 1) * 8
    circfill(bx_draw + 4, by_draw + 4, 3, 8)  -- box = red circle

    -- Draw the player (outlined circle) at (player_x, player_y)
    local px_draw = (player_x - 1) * 8
    local py_draw = (player_y - 1) * 8
    circ(px_draw + 4, py_draw + 4, 3, 7)       -- player = white circle

    -- HUD: level, remaining pushes, perfect pushes
    print("Lvl:" .. level_number, 1, 1, 7)
    print("Rem:" .. remaining_pushes, 1, 9, 7)
    print("Min:" .. perfect_pushes, 1, 17, 7)

  elseif game_state == GAME_STATE_GAMEOVER then
    -- Game Over Screen
    rectfill(0, 0, 127, 127, 0)                 -- black background
    print_centered("GAME OVER",  50, 8)
    print_centered("Press ❎ to Menu",  80, 7)
  end
end

-- helper: print text centered horizontally
function print_centered(txt, y, col)
  local x = flr((128 - #txt * 4) / 2)
  print(txt, x, y, col)
end

-- ============================================================================
-- 5) ENTRY POINT
-- ============================================================================

-- start in Main Menu
game_state = GAME_STATE_MENU



