-- sokoban_pcg.p8

-- constants
W = 16        -- total width including border
H = 16        -- total height including border
TILE_WALL  = 1
TILE_FLOOR = 0
TILE_GOAL  = 2

-- global state for current level
level_number     = 1
slack_initial    = 5   -- initial extra pushes beyond perfect
map              = {}  -- map[y][x]
box_x, box_y     = 0, 0
player_x, player_y = 0, 0
goal_x, goal_y   = 0, 0
perfect_pushes   = 0
remaining_pushes = 0

-- initialize blank map with borders
function init_map()
  for y=1,H do
    map[y] = {}
    for x=1,W do
      if x == 1 or x == W or y == 1 or y == H then
        map[y][x] = TILE_WALL
      else
        map[y][x] = TILE_FLOOR
      end
    end
  end

  -- Optionally: sprinkle interior walls at random for higher‐level difficulty
  -- for y=3,H-2 do
  --   for x=3,W-2 do
  --     if rnd() < 0.05 then map[y][x] = TILE_WALL end
  --   end
  -- end
end

-- pick a random interior floor tile
function choose_random_floor()
  local fx, fy
  repeat
    fx = flr(rnd(W-2)) + 2
    fy = flr(rnd(H-2)) + 2
  until map[fy][fx] == TILE_FLOOR
  return fx, fy
end

-- from (gx,gy), choose adjacent floor tile for the player
function choose_adjacent_floor(gx, gy)
  local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
  local shuffled = {}
  for i=1,#dirs do shuffled[i] = dirs[i] end
  -- shuffle them
  for i=#shuffled,2,-1 do
    local j = flr(rnd(i))+1
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end
  for _,d in ipairs(shuffled) do
    local px, py = gx + d[1], gy + d[2]
    if map[py][px] == TILE_FLOOR then
      return px, py
    end
  end
  -- if none, force choose any nearby floor (should not happen often)
  return gx+1, gy
end

-- is (x,y) walkable (floor or goal)?
function is_floor(x, y)
  return x >= 1 and x <= W and y >= 1 and y <= H and (map[y][x] == TILE_FLOOR or map[y][x] == TILE_GOAL)
end

-- simple integer random helper
function rnd_int(a, b)
  return flr(rnd(b - a + 1)) + a
end

-- reverse‐generate a puzzle of N pushes
function generate_puzzle(N)
  init_map()

  -- choose goal position
  goal_x, goal_y = choose_random_floor()
  map[goal_y][goal_x] = TILE_GOAL

  -- place box on goal
  box_x, box_y = goal_x, goal_y

  -- place player adjacent
  player_x, player_y = choose_adjacent_floor(goal_x, goal_y)

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
      -- restart if stuck
      return generate_puzzle(N)
    end

    local idx = rnd_int(1, #valid_dirs)
    local dx, dy = valid_dirs[idx][1], valid_dirs[idx][2]

    -- reverse push
    local new_bx = box_x - dx
    local new_by = box_y - dy
    local new_px = box_x
    local new_py = box_y

    box_x, box_y       = new_bx, new_by
    player_x, player_y = new_px, new_py

    count += 1
  end

  perfect_pushes = N

  -- sanity‐check using BFS solver
  local found = compute_min_pushes(player_x, player_y, box_x, box_y, goal_x, goal_y)
  if found == nil or found != N then
    -- generation error: retry
    return generate_puzzle(N)
  end

  -- determine allowed pushes = perfect + slack
  local slack = max(0, slack_initial - (level_number - 1))
  remaining_pushes = perfect_pushes + slack

  return
end

-- BFS helper: can the player go from (sx,sy) to (tx,ty) treating (bx,by) as a wall?
function can_player_reach(sx, sy, tx, ty, bx_block, by_block)
  local vis = {}
  for y=1,H do
    vis[y] = {}
    for x=1,W do
      vis[y][x] = false
    end
  end

  local q = {}
  add(q, {sx,sy})
  vis[sy][sx] = true

  while #q > 0 do
    local st = deli(q)
    local px, py = st[1], st[2]
    if px == tx and py == ty then
      return true
    end
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local nx, ny = px + d[1], py + d[2]
      if nx >=1 and nx <=W and ny>=1 and ny<=H then
        if not vis[ny][nx] and map[ny][nx] != TILE_WALL and not (nx == bx_block and ny == by_block) then
          vis[ny][nx] = true
          add(q, {nx, ny})
        end
      end
    end
  end

  return false
end

-- computes minimal pushes via BFS over (player,box) states
function compute_min_pushes(sx, sy, bx, by, gx, gy)
  -- 4D visited array: [py][px][by][bx]
  local visited = {}
  for py=1,H do
    visited[py] = {}
    for px=1,W do
      visited[py][px] = {}
      for by2=1,H do
        visited[py][px][by2] = {}
        for bx2=1,W do
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
    if cur_bx == gx and cur_by == gy then
      return pushes
    end

    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local dx, dy = d[1], d[2]
      local req_px = cur_bx - dx
      local req_py = cur_by - dy
      local new_bx = cur_bx + dx
      local new_by = cur_by + dy

      -- must have req_px,req_py inside floor
      if not is_floor(req_px, req_py) then
        goto dir_done
      end
      -- new box dest must be floor
      if not is_floor(new_bx, new_by) then
        goto dir_done
      end
      -- can player travel from (px,py) to (req_px,req_py)?
      if not can_player_reach(px, py, req_px, req_py, cur_bx, cur_by) then
        goto dir_done
      end

      -- new player after push = cur_bx,cur_by
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

-- handle player input & movement
function _update()
  if btnp(0) then try_move(-1, 0) end  -- left
  if btnp(1) then try_move(1, 0) end   -- right
  if btnp(2) then try_move(0, -1) end  -- up
  if btnp(3) then try_move(0, 1) end   -- down
end

function try_move(dx, dy)
  local tx = player_x + dx
  local ty = player_y + dy

  -- if moving into wall, stop
  if map[ty][tx] == TILE_WALL then return end

  -- if moving into the box
  if tx == box_x and ty == box_y then
    -- attempt to push
    local nbx, nby = box_x + dx, box_y + dy
    if not is_floor(nbx, nby) then
      return -- blocked
    end
    -- perform push
    box_x, box_y = nbx, nby
    player_x, player_y = tx, ty
    remaining_pushes -= 1

    -- check for win or loss
    check_end_conditions()
  else
    -- just walk
    player_x, player_y = tx, ty
  end
end

function check_end_conditions()
  if box_x == goal_x and box_y == goal_y then
    -- level complete
    level_number += 1
    generate_puzzle(perfect_pushes + 1)  -- or some function of level_number
  elseif remaining_pushes < 0 then
    -- fail → restart same level
    generate_puzzle(perfect_pushes)  -- regenerate a fresh puzzle of same length
  end
end

-- drawing code
function _draw()
  cls()
  for y=1,H do
    for x=1,W do
      local t = map[y][x]
      if t == TILE_WALL then
        rectfill((x-1)*8, (y-1)*8, (x)*8-1, (y)*8-1, 5)  -- wall color
      elseif t == TILE_GOAL then
        rect((x-1)*8, (y-1)*8, (x)*8-1, (y)*8-1, 11) -- goal color
      else
        rectfill((x-1)*8, (y-1)*8, (x)*8-1, (y)*8-1, 0)  -- floor = black
      end
    end
  end

  -- draw box
  local bx_draw = (box_x-1)*8
  local by_draw = (box_y-1)*8
  --rect(bx_draw, by_draw, bx_draw+7, by_draw+7, 8)
  circfill(bx_draw+4, by_draw+4, 3, 8);

  -- draw player
  local px_draw = (player_x-1)*8
  local py_draw = (player_y-1)*8
  circ(px_draw+4, py_draw+4, 3, 7)

  -- draw HUD: remaining pushes
  print("Level:"..level_number, 1, 1, 7)
  print("Rem Pushes:"..remaining_pushes, 1, 9, 7)
  print("Min Pushes:"..perfect_pushes, 1, 17, 7)
end

-- start the first level
generate_puzzle(3)  -- e.g. start with N=3 pushes
