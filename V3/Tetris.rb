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
  HIGHSCORE_FILE = "highscore.ths"
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
    @highscore = load_highscore

    loop do
      reset_game
      run
      game_over_screen
      break unless retry_prompt
    end

    close_screen
  end

  def load_highscore
    if File.exist?(HIGHSCORE_FILE)
      data = File.read(HIGHSCORE_FILE)
        result = data.unpack1(L) rescue nil
      return data.unpack1("L") rescue 0
    else
      return 0
    end
  end

  def save_highscore
    return unless @score > @highscore

    File.open(HIGHSCORE_FILE, 'wb') do |f|
      f.write([@score].pack("L"))  # Unsigned 32-bit Integer
    end

  @highscore = @score
  end

  def reset_game
    @board = Array.new(HEIGHT) { Array.new(WIDTH) { [0, 0] } }
    @score = load_highscore
    @level = (@score / 1000) + 1
    @lines_cleared = 0
    @last_drop = Time.now
    @fall_speed = [INITIAL_SPEED - (@level * 0.05), 0.1].max
    @next_block, @next_color = generate_block
    @held_block = nil
    @held_color = nil
    @hold_used = false  # ホールド連続使用防止用フラグ
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
    @hold_used = false  # 新ブロック出現でホールド可能に戻す
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
        if cell == 1
          @board[@y + dy][@x + dx] = [1, @color]
        end
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
    @level = (@score / 1000) + 1
    @fall_speed = [INITIAL_SPEED - (@level * 0.05), 0.1].max
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

    # 盤面描画
    @board.each_with_index do |row, y|
      row.each_with_index do |(cell, color), x|
        if cell == 1
          @win.setpos(y, x * 2 + 1)
          @win.attron(color_pair(color)) { @win.addstr("[]") }
        end
      end
    end

    # ゴーストブロック描画
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

    # 現在のブロック描画
    @block.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        if cell == 1
          @win.setpos(@y + dy, (@x + dx) * 2 + 1)
          @win.attron(color_pair(@color)) { @win.addstr("[]") }
        end
      end
    end

    # 次のブロック表示
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

    # ホールド表示
    if @held_block
      @win.setpos(1, WIDTH * 2 + 14)
      @win.addstr("Hold:")
      @held_block.each_with_index do |row, dy|
        row.each_with_index do |cell, dx|
          if cell == 1
            @win.setpos(2 + dy, WIDTH * 2 + 14 + dx * 2)
            @win.attron(color_pair(@held_color)) { @win.addstr("[]") }
          end
        end
      end
    end

    # スコア・レベル・ハイスコア表示
    @win.setpos(8, WIDTH * 2 + 4)
    @win.addstr("Score: #{@score}")
    @win.setpos(9, WIDTH * 2 + 4)
    @win.addstr("Level: #{@level}")
    @win.setpos(10, WIDTH * 2 + 4)
    @win.addstr("Highscore: #{@highscore}")

    @win.refresh
  end

  def game_over
    @game_over = true
  end

  def game_over_screen
    save_highscore
    @win.clear
    @win.setpos(HEIGHT / 2 - 2, WIDTH)
    @win.addstr("Game Over!")
    @win.setpos(HEIGHT / 2 - 1, WIDTH)
    @win.addstr("Score: #{@score}")
    @win.setpos(HEIGHT / 2, WIDTH)
    @win.addstr("Highscore: #{@highscore}")
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
    return if @hold_used

    if @held_block.nil?
      @held_block = @block.map(&:dup)
      @held_color = @color
      spawn_block
    else
      temp_block = @block
      temp_color = @color
      @block = @held_block
      @color = @held_color
      @held_block = temp_block
      @held_color = temp_color
      @x = WIDTH / 2 - @block[0].size / 2
      @y = 0
      game_over if collision?(@x, @y, @block)
  end

  @hold_used = true
end

end

Tetris.new
