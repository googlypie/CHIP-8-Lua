local cpu = {
    ram = {},
    reg = {},
    idx = 0,
    pc = 0x200,
    stack = {},
    sp = 0,
    del_timer = 0,
    aud_timer = 0,
    disp = {},
    halt = false,
    s_mode = 0,
    cps = 0,
    keys = {},
    pause = false,
    key_tar = 0
}

local function sleep(seconds)
    local start = os.clock()
    repeat until os.clock() - start >= seconds
end

local key_map = {
    ["1"] = 0x1, ["2"] = 0x2, ["3"] = 0x3, ["4"] = 0xC,
    ["q"] = 0x4, ["w"] = 0x5, ["e"] = 0x6, ["r"] = 0xD,
    ["a"] = 0x7, ["s"] = 0x8, ["d"] = 0x9, ["f"] = 0xE,
    ["z"] = 0xA, ["x"] = 0x0, ["c"] = 0xB, ["v"] = 0xF
}

local timer = 0

local debug = false

local beep

local instructions = {
    [0x0] = function(x, y, n, nn, nnn)
        if nn == 0xE0 then
            for y = 0, 31 do
                for x = 0, 63 do
                    cpu.disp[y][x] = 0
                end
            end
            if debug then print("(op 0) cls") end
        elseif nn == 0xEE then
            cpu.sp = cpu.sp - 1
            cpu.pc = cpu.stack[cpu.sp]
            if debug then print("(op 0) return from subroutine") end
        end
    end,
    [0x1] = function(x, y, n, nn, nnn)
        cpu.pc = nnn
        if debug then print("(op 1) jp to line " .. string.format(nnn)) end
    end,
    [0x2] = function(x, y, n, nn, nnn)
        cpu.stack[cpu.sp] = cpu.pc
        cpu.sp = cpu.sp + 1
        cpu.pc = nnn
        if debug then print("(op 2) jump to subroutine at line " .. string.format(nnn)) end
    end,
    [0x3] = function(x, y, n, nn, nnn)
        if debug then print("(op 3) check") end
        if cpu.reg[x] == nn then
            cpu.pc = cpu.pc + 2
            if debug then print("(op 3) skipped cmd") end
        end
    end,
    [0x4] = function(x, y, n, nn, nnn)
        if debug then print("(op 4) check") end
        if cpu.reg[x] ~= nn then
            cpu.pc = cpu.pc + 2
            if debug then print("(op 4) skipped cmd") end
        end
    end,
    [0x5] = function(x, y, n, nn, nnn)
        if debug then print("(op 5) check") end
        if cpu.reg[x] == cpu.reg[y] then
            cpu.pc = cpu.pc + 2
            if debug then print("(op 5) skipped cmd") end
        end
    end,
    [0x6] = function(x, y, n, nn, nnn)
        cpu.reg[x] = nn
        if debug then print("(op 6) set V" .. string.format("%x", x):upper() .. " " .. string.format(nn)) end
    end,
    [0x7] = function(x, y, n, nn, nnn)
        cpu.reg[x] = bit.band(cpu.reg[x] + nn, 255)
        if debug then print("(op 7) add to V" .. string.format("%x", x):upper() .. " " .. string.format(nn)) end
        --print(cpu.reg[x])
    end,
    [0x8] = function(x, y, n, nn, nnn)
        if n == 0x0 then
            cpu.reg[x] = cpu.reg[y]
            if debug then print("(op 8) V" .. string.format("%x", x):upper() .. " equals V" .. string.format("%x", y):upper()) end
        elseif n == 0x1 then
            cpu.reg[x] = bit.bor(cpu.reg[x], cpu.reg[y])
            if debug then print("(op 8) V" .. string.format("%x", x) .. " equals V" .. string.format("%x", x):upper() .. " OR V" .. string.format("%x", y):upper()) end
        elseif n == 0x2 then
            cpu.reg[x] = bit.band(cpu.reg[x], cpu.reg[y])
            if debug then print("(op 8) VX equals VX AND VY") end
        elseif n == 0x3 then
            cpu.reg[x] = bit.bxor(cpu.reg[x], cpu.reg[y])
            if debug then print("(op 8) VX equals VX XOR VY") end
        elseif n == 0x4 then
            local sum = cpu.reg[x] + cpu.reg[y]
            if sum > 255 then
                cpu.reg[0xF] = 1
                if debug then print("(op 8) VX equals VX plus VY [carry]") end
            else
                cpu.reg[0xF] = 0
                if debug then print("(op 8) VX equals VX plus VY [no carry]") end
            end
            cpu.reg[x] = bit.band(sum, 255)
        elseif n == 0x5 then
            if cpu.reg[x] >= cpu.reg[y] then
                cpu.reg[0xF] = 1
                if debug then print("(op 8) VX equals VX minus VY [no borrow]") end
            else
                cpu.reg[0xF] = 0
                if debug then print("(op 8) VX equals VX minus VY [borrow]") end
            end
            cpu.reg[x] = bit.band(cpu.reg[x] - cpu.reg[y], 255)
        elseif n == 0x6 then
            if cpu.s_mode == 0 then
                cpu.reg[0xF] = bit.band(cpu.reg[y], 1)
                cpu.reg[x] = bit.rshift(cpu.reg[y], 1)
                if debug then print("(op 8) VX equals VY shifted right [original shift]") end
            else
                cpu.reg[0xF] = bit.band(cpu.reg[x], 1)
                cpu.reg[x] = bit.rshift(cpu.reg[x], 1)
                if debug then print("(op 8) VX equals VX shifted right [modern shift]") end
            end
        elseif n == 0x7 then
            if cpu.reg[y] >= cpu.reg[x] then
                cpu.reg[0xF] = 1
                if debug then print("(op 8) VX equals VY minus VX [no borrow]") end
            else
                cpu.reg[0xF] = 0
                if debug then print("(op 8) VX equals VY minus VX [borrow]") end
            end
            cpu.reg[x] = bit.band(cpu.reg[y] - cpu.reg[x], 255)
        elseif n == 0xE then
            if cpu.s_mode == 0 then
                cpu.reg[0xF] = bit.rshift(bit.band(cpu.reg[y], 0x80), 7)
                cpu.reg[x] = bit.band(bit.lshift(cpu.reg[y], 1), 255)
                if debug then print("(op 8) VX equals VY shifted left [original shift]") end
            else
                cpu.reg[0xF] = bit.rshift(bit.band(cpu.reg[x], 0x80), 7)
                cpu.reg[x] = bit.band(bit.lshift(cpu.reg[x], 1), 255)
                if debug then print("(op 8) VX equals VX shifted left [modern shift]") end
            end
        end
    end,
    [0x9] = function(x, y, n, nn, nnn)
        if debug then print("(op 9) check") end
        if cpu.reg[x] ~= cpu.reg[y] then
            cpu.pc = cpu.pc + 2
            if debug then print("(op 9) skipped cmd") end
        end
    end,
    [0xA] = function(x, y, n, nn, nnn)
        cpu.idx = nnn
        if debug then print("(op A) register i equals " .. string.format(nnn)) end
    end,
    [0xB] = function(x, y, n, nn, nnn)
        cpu.pc = nnn + cpu.reg[0x0]
        if debug then print("(op B) PC equals NNN plus V0") end
    end,
    [0xC] = function(x, y, n, nn, nnn)
        local rand = math.random(0, 255)
        cpu.reg[x] = bit.band(rand, nn)
        if debug then print("(op C) VX equals random 0/255 with mask of " .. string.format(nn)) end
    end,
    [0xD] = function(x, y, n, nn, nnn)
        local stx = cpu.reg[x] % 64
        local sty = cpu.reg[y] % 32
        cpu.reg[0xF] = 0
        if debug then print("(op D) draw sprite at " .. string.format(cpu.reg[x]) .. ", " .. string.format(cpu.reg[y]) .. " at memory address " .. string.format(cpu.idx) .. " with height " .. string.format(nn)) end

        for row = 0, n - 1 do
            local s_byte = cpu.ram[cpu.idx + row]
            for col = 0, 7 do
                if bit.band(s_byte, bit.rshift(0x80, col)) ~= 0 then
                    local px = (stx + col) % 64
                    local py = (sty + row) % 32

                    if cpu.disp[py][px] == 1 then
                        cpu.reg[0xF] = 1
                        cpu.disp[py][px] = 0
                    else
                        cpu.disp[py][px] = 1
                    end
                end
            end
        end
    end,
    [0xE] = function(x, y, n, nn, nnn)
        local kidx = cpu.reg[x]

        if nn == 0x9E then
            if debug then print("(op E) check if key " .. string.format(cpu.reg[x]) .. " is pressed") end
            if cpu.keys[kidx] then
                cpu.pc = cpu.pc + 2
            end
        elseif nn == 0xA1 then
            if debug then print("(op E) check if key " .. string.format(cpu.reg[x]) .. " is not pressed") end
            if not cpu.keys[kidx] then
                cpu.pc = cpu.pc + 2
            end
        end
    end,
    [0xF] = function(x, y, n, nn, nnn)
        if nn == 0x07 then
            cpu.reg[x] = cpu.del_timer
            if debug then print("(op F) set delay timer to VX") end
        elseif nn == 0x0A then
            cpu.pause = true
            cpu.key_tar = x
            if debug then print("(op F) check if key pressed") end
        elseif nn == 0x15 then
            if debug then print("(op F) delay timer equals V" .. string.format("%x", x):upper()) end
            cpu.del_timer = cpu.reg[x]
        elseif nn == 0x18 then
            if debug then print("(op F) sound timer equals V" .. string.format("%x", x):upper()) end
            cpu.aud_timer = cpu.reg[x]
        elseif nn == 0x1E then
            if debug then print("(op F) add register i with V" .. string.format("%x", x):upper()) end
            cpu.idx = bit.band(cpu.idx + cpu.reg[x], 0x0FFF)
        elseif nn == 0x29 then
            if debug then print("(op F) set register i to address of character " .. string.format(cpu.reg[x]) .. " in memory") end
            local char = bit.band(cpu.reg[x], 0x0F)
            cpu.idx = char * 5
        elseif nn == 0x33 then
            local val = cpu.reg[x]
            cpu.ram[cpu.idx] = math.floor(val / 100)
            cpu.ram[cpu.idx + 1] = math.floor((val % 100) / 10)
            cpu.ram[cpu.idx + 2] = val % 10
        elseif nn == 0x55 then
            for i = 0, x do
                cpu.ram[cpu.idx + i] = cpu.reg[i]
            end
            if cpu.s_mode == 0 then
                cpu.idx = cpu.idx + x + 1
            end
        elseif nn == 0x65 then
            for i = 0, x do
                cpu.reg[i] = cpu.ram[cpu.idx + i]
            end
            if cpu.s_mode == 0 then
                cpu.idx = cpu.idx + x + 1
            end
        end
    end,
}

local function init_rom(name)
    local program = {}
    local file = io.open(name, "rb")
    if file then
        local cont = file:read("*all")
        file:close()
        for i=1,#cont do
            program[i] = string.byte(cont, i)
        end
        return program
    else
        print("flash prog fail")
        print("file not found")
        print("filename is wrong, or file does not exist")
        print("consider renaming to \"prog.ch8\" if it exists")
        return nil
    end
end

local prog = init_rom("prog.ch8")

function cpu.load_prog(program)
    local y = 0
    for i=1,#program do
        cpu.ram[0x200 + (i - 1)] = program[i]
        if i >= y*4 then
            y = y + 1
            sleep(0.001)
        end
    end
end

function cpu.init()
    math.randomseed(os.time())
    print("init mem...")
    for i=0,4095 do cpu.ram[i]=0 end
    for i=0,15 do cpu.reg[i]=0 end
    for y = 0, 31 do
        cpu.disp[y] = {}
        for x = 0, 63 do
            cpu.disp[y][x] = 0
        end
    end

    local font = {
        0xF0, 0x90, 0x90, 0x90, 0xF0, -- 0
        0x20, 0x60, 0x20, 0x20, 0x70, -- 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, -- 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, -- 3
        0x90, 0x90, 0xF0, 0x10, 0x10, -- 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, -- 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, -- 6
        0xF0, 0x10, 0x20, 0x40, 0x40, -- 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, -- 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, -- 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, -- A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, -- B
        0xF0, 0x80, 0x80, 0x80, 0xF0, -- C
        0xE0, 0x90, 0x90, 0x90, 0xE0, -- D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, -- E
        0xF0, 0x80, 0xF0, 0x80, 0x80, -- F
    }
    print("flash font...")
    for k, v in ipairs(font) do
        cpu.ram[k-1] = v
    end
    print("flash prog...")
    cpu.load_prog(prog)
    print("get settings...")
    local file = io.open("config.txt", "r")
    if not file then return end
    for line in file:lines() do
        if line:find("shift_mode") then
            if line:lower():find("original") then
                cpu.s_mode = 0
            else
                cpu.s_mode = 1
            end
        end
        if line:find("cycles_per_step") then
            local val = string.sub(line, 19, #line)
            cpu.cps = val
        end
    end
    print(cpu.cps, cpu.s_mode)
    file:close()
    print("initialized!")
end

function cpu.cycle(cmd)
    if cpu.pause then
        for i = 0, #cpu.keys do
            if cpu.keys[i] == true then
                cpu.reg[cpu.key_tar] = i
                cpu.pause = false
                return
            end
        end
        return
    end
    local h = cpu.ram[cpu.pc]
    local l = cpu.ram[cpu.pc + 1]
    local c = bit.bor(bit.lshift(h, 8), l)

    local op = bit.band(c, 0xF000)

    local x = bit.rshift(bit.band(c, 0x0F00), 8)
    local y = bit.rshift(bit.band(c, 0x00F0), 4)
    local n = bit.band(c, 0x000F)
    local nn = bit.band(c, 0x00FF)
    local nnn = bit.band(c, 0x0FFF)

    local func = instructions[bit.rshift(op, 12)]

    if cpu.pause == false then
        cpu.pc = cpu.pc + 2
    end

    if func then
        func(x, y, n, nn, nnn)
    else
        print(string.format("unknown command at byte %04X", cpu.pc-2))
        cpu.halt = true
    end
end

function love.load()
    cpu.init()
    --[[for i, v in ipairs(cpu.ram) do
        print("line: " .. string.format(i) .. "   value: " .. string.format(v))
    end]]--
    -- Audio Generation
    local sample_rate = 44100
    local freq = 440 
    local length = 0.1 -- Buffer length
    local samples = math.floor(sample_rate * length)
    local data = love.sound.newSoundData(samples, sample_rate, 16, 1)
    
    for i = 0, samples - 1 do
        -- Create a square wave: toggle between positive and negative
        local val = math.sin(i * (freq * math.pi * 2) / sample_rate)
        data:setSample(i, val > 0 and 0.1 or -0.1) 
    end
    
    beep = love.audio.newSource(data)
    beep:setLooping(true)

    love.window.setMode(640, 320)
end

function love.update(dt)
    for i=0,cpu.cps do
        if cpu.pc <= 4095 and cpu.halt == false then
            --print(cpu.pc)
            cpu.cycle()
        end
    end

    timer = timer + dt
    if timer >= 1/60 then
        if cpu.del_timer > 0 then cpu.del_timer = cpu.del_timer - 1 end
        if cpu.aud_timer > 0 then cpu.aud_timer = cpu.aud_timer - 1 end
        timer = timer - 1/60
    end
    if cpu.aud_timer > 0 then
        beep:play()
    else
        beep:stop()
    end
    sleep(1/60)
end

function love.draw()
    for y = 0, 31 do
        for x = 0, 63 do
            if cpu.disp[y][x] == 1 then
                love.graphics.rectangle("fill", x*10, y*10, 10, 10)
            end
        end
    end
end

function love.keypressed(key)
    if key_map[key] then cpu.keys[key_map[key]] = true end
end

function love.keyreleased(key)
    if key_map[key] then cpu.keys[key_map[key]] = false end
end