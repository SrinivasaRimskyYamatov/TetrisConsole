require 'curses'
include Curses

BLOCKS = [
  [[1, 1, 1, 1]],                      # I
  [[1, 1], [1, 1]],                    # O
  [[0, 1, 0], [1, 1, 1]],              # T
  [[1, 1, 0], [0, 1, 1]],              # Z
  [[0, 1, 1], [1, 1, 0]],              # S
  [[1, 0, 0], [1, 1, 1]],              # J
  [[0, 0, 1], [1, 1, 1]]               # L
]

COLORS = [COLOR_CYAN, COLOR_YELLOW, COLOR_MAGENTA, COLOR_RED, COLOR_GREEN, COLOR_BLUE, COLOR_WHITE]

class Tetris
  WIDTH = 10
  HEIGHT = 20
  INITIAL_SPEED = 0.5

  def initialize
    init_screen
    start_color
    cbreak
    noecho
    curs_set(0)
    stdscr.keypad(true)
    stdscr.timeout = 50

    COLORS.each_with_index do |c, i|
      init_pair(i + 1, c, COLOR_BLACK)
    end

    @win = stdscr

    loop do
      reset_game
      run
      game_over_screen
      break unless retry_prompt
    end
    close_screen
  end

  def reset_game
    @board = Array.new(HEIGHT) { Array.new(WIDTH) { [0, 0] } }
    @score = 0
    @level = 1
    @lines_cleared = 0
    @last_drop = Time.now
    @fall_speed = INITIAL_SPEED
    @next_block, @next_color = generate_block
    spawn_block
  end

  def generate_block
    [BLOCKS.sample.map(&:dup), rand(1..7)]
  end

  def spawn_block
    @block, @color = @next_block, @next_color
    @next_block, @next_color = generate_block
    @x = WIDTH / 2 - @block[0].size / 2
    @y = 0
    game_over if collision?(@x, @y, @block)
  end

  def rotate(block)
    block[0].zip(*block[1..]).map(&:reverse)
  end

  def collision?(x, y, block)
    block.each_with_index.any? do |row, dy|
      row.each_with_index.any? do |cell, dx|
        next false if cell == 0
        bx = x + dx
        by = y + dy
        bx < 0 || bx >= WIDTH || by >= HEIGHT || (by >= 0 && @board[by][bx][0] == 1)
      end
    end
  end

  def fix_block
    @block.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        @board[@y + dy][@x + dx] = [1, @color] if cell == 1
      end
    end
    clear_lines
    spawn_block
  end

  def clear_lines
    new_board = @board.reject do |row|
      full = row.all? { |cell, _| cell == 1 }
      beep if full
      full
    end
    cleared = HEIGHT - new_board.size
    @score += cleared * 100
    @lines_cleared += cleared
    @level = (@lines_cleared / 10) + 1
    @fall_speed = [INITIAL_SPEED - (@level * 0.05), 0.1].max  # 最低速度0.1秒
    @board = Array.new(cleared) { Array.new(WIDTH) { [0, 0] } } + new_board
  end

  def draw
    @win.clear

    # 枠線
    (0..HEIGHT).each do |y|
      @win.setpos(y, 0)
      @win.addstr("|")
      @win.setpos(y, WIDTH * 2 + 1)
      @win.addstr("|")
    end
    (0..WIDTH).each do |x|
      @win.setpos(HEIGHT, x * 2)
      @win.addstr("--")
    end

    # 盤面
    @board.each_with_index do |row, y|
      row.each_with_index do |(cell, color), x|
        if cell == 1
          @win.setpos(y, x * 2 + 1)
          @win.attron(color_pair(color)) { @win.addstr("[]") }
        end
      end
    end

    # ゴーストブロック
    ghost_y = @y
    while !collision?(@x, ghost_y + 1, @block)
      ghost_y += 1
    end
    @block.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        if cell == 1
          @win.setpos(ghost_y + dy, (@x + dx) * 2 + 1)
          @win.attron(color_pair(0)) { @win.addstr("[]") }
        end
      end
    end

    # 現在のブロック
    @block.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        if cell == 1
          @win.setpos(@y + dy, (@x + dx) * 2 + 1)
          @win.attron(color_pair(@color)) { @win.addstr("[]") }
        end
      end
    end

    # 次のブロック
    @win.setpos(1, WIDTH * 2 + 4)
    @win.addstr("Next:")
    @next_block.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        if cell == 1
          @win.setpos(2 + dy, WIDTH * 2 + 4 + dx * 2)
          @win.attron(color_pair(@next_color)) { @win.addstr("[]") }
        end
      end
    end

    # ホールドされたブロック (Nextの右隣)
    if @held_block
      @win.setpos(1, WIDTH * 2 + 12)  # 次のブロックの右隣にホールドを表示
      @win.addstr("Hold:")
      @held_block.each_with_index do |row, dy|
        row.each_with_index do |cell, dx|
          if cell == 1
            @win.setpos(2 + dy, WIDTH * 2 + 12 + dx * 2)
            @win.attron(color_pair(@held_color)) { @win.addstr("[]") }
          end
        end
      end
    end

    # スコア表示
    @win.setpos(8, WIDTH * 2 + 4)
    @win.addstr("Score: #{@score}")
    @win.setpos(9, WIDTH * 2 + 4)
    @win.addstr("Level: #{@level}")

    @win.refresh
  end

  def game_over
    @game_over = true
  end

  def game_over_screen
    @win.clear
    @win.setpos(HEIGHT / 2 - 1, WIDTH)
    @win.addstr("Game Over!")
    @win.setpos(HEIGHT / 2, WIDTH)
    @win.addstr("Score: #{@score}")
    @win.setpos(HEIGHT / 2 + 1, WIDTH)
    @win.addstr("Press 'r' to retry, 'q' to quit")
    @win.refresh
  end

  def retry_prompt
    loop do
      case @win.getch
      when 'r' then return true
      when 'q' then return false
      end
    end
  end

  def run
    @game_over = false
    loop do
      draw
      break if @game_over

      now = Time.now
      if now - @last_drop >= @fall_speed
        if collision?(@x, @y + 1, @block)
          fix_block
        else
          @y += 1
        end
        @last_drop = now
      end

      case @win.getch
      when Key::LEFT
        @x -= 1 unless collision?(@x - 1, @y, @block)
      when Key::RIGHT
        @x += 1 unless collision?(@x + 1, @y, @block)
      when Key::DOWN
        if collision?(@x, @y + 1, @block)
          fix_block
        else
          @y += 1
        end
      when Key::UP
        new_block = rotate(@block)
        @block = new_block unless collision?(@x, @y, new_block)
      when ' '  # ハードドロップ
        while !collision?(@x, @y + 1, @block)
          @y += 1
        end
        fix_block
      when 'p'  # 一時停止
        pause_game
      when 'z'  # ホールド
        hold_block
      end

      sleep(0.03)
    end
  end

  def pause_game
    @win.clear
    @win.setpos(HEIGHT / 2, WIDTH)
    @win.addstr("Paused")
    @win.setpos(HEIGHT / 2 + 1, WIDTH)
    @win.addstr("Press 'p' again to resume")
    @win.refresh
    loop do
      break if @win.getch == 'p'
    end
  end

  def hold_block
    if @held_block.nil?
      @held_block, @held_color = @block, @color
      spawn_block
    else
      @block, @color = @held_block, @held_color
      @held_block, @held_color = nil, nil
      @x = WIDTH / 2 - @block[0].size / 2
      @y = 0
      game_over if collision?(@x, @y, @block)
    end
  end
end

Tetris.new
