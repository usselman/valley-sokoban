-- sokoban_pcg.p8

-- constants
W = 16        -- total width including border
H = 16        -- total height including border

TILE_WALL  = 1
TILE_FLOOR = 0
TILE_GOAL  = 2

-- game states
GAME_STATE_MENU     = 0
GAME_STATE_LOADING  = 1
GAME_STATE_PLAY     = 2
GAME_STATE_GAMEOVER = 3

-- global state
game_state         = GAME_STATE_MENU
level_number       = 1          -- current level index (starts at 1)
base_push_count    = 3          -- starting “perfect pushes” for level 1
slack_initial      = 5          -- initial extra pushes beyond perfect
map                = {}         -- map[y][x] array
floor_list         = {}         -- list of all floor coords for quick sampling
box_x, box_y       = 0, 0
player_x, player_y = 0, 0
goal_x, goal_y     = 0, 0
perfect_pushes     = 0          -- known minimum pushes for current puzzle
remaining_pushes   = 0          -- how many pushes the player still has
next_push_count    = 0          -- temp storage for N when loading

-- ============================================================================
-- 1) MAP INITIALIZATION AND OBSTACLE GENERATION (with floor_list)
-- ============================================================================

function init_map()
  -- clear floor_list
  floor_list = {}

  for y = 1, H do
    map[y] = {}
    for x = 1, W do
      if x == 1 or x == W or y == 1 or y == H then
        map[y][x] = TILE_WALL
      else
        map[y][x] = TILE_FLOOR
        add(floor_list, {x, y})
      end
    end
  end

  -- sprinkle obstacles (walls) based on level_number
  -- p = min(0.30, 0.04 * level_number)
  local p = min(0.30, 0.04 * level_number)
  -- iterate interior and occasionally turn FLOOR -> WALL
  for i = #floor_list, 1, -1 do
    local coord = floor_list[i]
    local x, y = coord[1], coord[2]
    if rnd() < p then
      map[y][x] = TILE_WALL
      deli(floor_list, i)  -- remove from floor_list
    end
  end
end

-- pick a random floor tile by indexing floor_list
function choose_random_floor()
  local idx = rnd_int(1, #floor_list)
  local coord = floor_list[idx]
  return coord[1], coord[2]
end

-- given (gx, gy), pick a random adjacent floor tile for player
function choose_adjacent_floor(gx, gy)
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  -- shuffle dirs
  for i = #dirs, 2, -1 do
    local j = rnd_int(1, i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  for _, d in ipairs(dirs) do
    local px, py = gx + d[1], gy + d[2]
    if map[py][px] == TILE_FLOOR then
      return px, py
    end
  end
  -- fallback: scan floor_list for any not adjacent to walls
  for _, coord in ipairs(floor_list) do
    local x, y = coord[1], coord[2]
    if abs(x - gx) + abs(y - gy) == 1 then
      return x, y
    end
  end
  -- worst‐case: return first floor
  return floor_list[1][1], floor_list[1][2]
end

-- check if (x,y) is floor or goal
function is_floor(x, y)
  return x >= 1 and x <= W and y >= 1 and y <= H and (map[y][x] == TILE_FLOOR or map[y][x] == TILE_GOAL)
end

-- simple integer random in [a..b]
function rnd_int(a, b)
  return flr(rnd(b - a + 1)) + a
end

-- ============================================================================
-- 2) PUZZLE GENERATION VIA REVERSE PUSH (no BFS validation)
-- ============================================================================

function generate_puzzle(N)
  --
  -- 1) Rebuild map & floor_list
  --
  init_map()

  --
  -- 2) Place goal on random floor
  --
  goal_x, goal_y = choose_random_floor()
  map[goal_y][goal_x] = TILE_GOAL
  -- remove goal from floor_list so box won't land there initially
  for i = #floor_list, 1, -1 do
    if floor_list[i][1] == goal_x and floor_list[i][2] == goal_y then
      deli(floor_list, i)
      break
    end
  end

  --
  -- 3) Start with box on goal, choose player adjacent
  --
  box_x, box_y = goal_x, goal_y
  player_x, player_y = choose_adjacent_floor(goal_x, goal_y)

  --
  -- 4) Perform N reverse pushes
  --
  local count = 0
  while count < N do
    local valid_dirs = {}
    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local dx, dy = d[1], d[2]
      local px_cand = box_x - dx
      local py_cand = box_y - dy
      local bx_cand = box_x + dx
      local by_cand = box_y + dy

      if is_floor(px_cand, py_cand) and is_floor(bx_cand, by_cand) then
        add(valid_dirs, {dx, dy})
      end
    end

    if #valid_dirs == 0 then
      -- no valid reverse push → retry entire generation
      return generate_puzzle(N)
    end

    local idx = rnd_int(1, #valid_dirs)
    local dx, dy = valid_dirs[idx][1], valid_dirs[idx][2]
    local new_bx = box_x - dx
    local new_by = box_y - dy
    local new_px = box_x
    local new_py = box_y

    box_x, box_y       = new_bx, new_by
    player_x, player_y = new_px, new_py
    count += 1
  end

  --
  -- 5) Set perfect_pushes and remaining_pushes
  --
  perfect_pushes = N
  local slack = max(0, slack_initial - (level_number - 1))
  remaining_pushes = perfect_pushes + slack
end

-- ============================================================================
-- 3) INPUT HANDLING AND GAME‐STATE TRANSITIONS
-- ============================================================================

function _update()
  if game_state == GAME_STATE_MENU then
    if btnp(5) then
      level_number = 1
      next_push_count = base_push_count + level_number
      game_state = GAME_STATE_LOADING
    end

  elseif game_state == GAME_STATE_LOADING then
    generate_puzzle(next_push_count)
    game_state = GAME_STATE_PLAY

  elseif game_state == GAME_STATE_PLAY then
    if btnp(0) then try_move(-1, 0) end
    if btnp(1) then try_move(1, 0) end
    if btnp(2) then try_move(0, -1) end
    if btnp(3) then try_move(0, 1) end

  elseif game_state == GAME_STATE_GAMEOVER then
    if btnp(5) then
      game_state = GAME_STATE_MENU
    end
  end
end

function try_move(dx, dy)
  local tx = player_x + dx
  local ty = player_y + dy

  if map[ty][tx] == TILE_WALL then
    return
  end

  if tx == box_x and ty == box_y then
    local nbx, nby = box_x + dx, box_y + dy
    if not is_floor(nbx, nby) then return end
    box_x, box_y       = nbx, nby
    player_x, player_y = tx, ty
    remaining_pushes -= 1
    check_end_conditions()
  else
    player_x, player_y = tx, ty
  end
end

function check_end_conditions()
  if box_x == goal_x and box_y == goal_y then
    level_number += 1
    next_push_count = base_push_count + level_number
    game_state = GAME_STATE_LOADING
  elseif remaining_pushes < 0 then
    game_state = GAME_STATE_GAMEOVER
  end
end

-- ============================================================================
-- 4) DRAWING EACH GAME STATE
-- ============================================================================

function _draw()
  cls()
  if game_state == GAME_STATE_MENU then
    rectfill(0, 0, 127, 127, 0)
    print_centered("SOKOBAN PCG",        40, 7)
    print_centered("A Procedural Puzzle", 52, 6)
    print_centered("Press ❎ to Start",    80, 7)

  elseif game_state == GAME_STATE_LOADING then
    rectfill(0, 0, 127, 127, 0)
    local chars = {"/", "-", "\\", "|"}
    local idx = flr(time() * 10) % 4 + 1
    print_centered("Loading " .. chars[idx], 60, 7)

  elseif game_state == GAME_STATE_PLAY then
    for y = 1, H do
      for x = 1, W do
        local t = map[y][x]
        local sx = (x - 1) * 8
        local sy = (y - 1) * 8
        if t == TILE_WALL then
          --rectfill(sx, sy, sx + 7, sy + 7, 5)
          spr(001, sx, sy, 1, 1, 5)
        elseif t == TILE_GOAL then
          rect(sx, sy, sx + 7, sy + 7, 11)
        else
          rectfill(sx, sy, sx + 7, sy + 7, 0)
        end
      end
    end

    local bx_draw = (box_x - 1) * 8
    local by_draw = (box_y - 1) * 8
    circfill(bx_draw + 4, by_draw + 4, 3, 8)

    local px_draw = (player_x - 1) * 8
    local py_draw = (player_y - 1) * 8
    --circ(px_draw + 4, py_draw + 4, 3, 7)
    spr(002, px_draw, py_draw, 1, 1, 7)

    print("Lvl:" .. level_number,     1,  1, 7)
    print("Rem:" .. remaining_pushes, 1,  9, 7)
    print("Min:" .. perfect_pushes,   1, 17, 7)

  elseif game_state == GAME_STATE_GAMEOVER then
    rectfill(0, 0, 127, 127, 0)
    print_centered("GAME OVER",       50, 8)
    print_centered("Press ❎ to Menu", 80, 7)
  end
end

function print_centered(txt, y, col)
  local x = flr((128 - #txt * 4) / 2)
  print(txt, x, y, col)
end

-- ============================================================================
-- 5) ENTRY POINT
-- ============================================================================

game_state = GAME_STATE_MENU
