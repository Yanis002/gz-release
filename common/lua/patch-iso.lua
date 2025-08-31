function usage()
io.stderr:write("usage: make-iso [<gzinject-arg>...] [--no-trim]"
                .. " [-m <input-rom>] [--mq-rom <input-rom>] [-o <output-iso>] <input-iso>\n")
os.exit(1)
end

-- parse arguments
local arg = {...}
local opt_id
local opt_title
local opt_directory = "isoextract"
local opt_raphnet
local opt_disable_controller_remappings
local opt_no_trim
local opt_rom
local opt_mq_rom
local opt_out
local opt_iso
local opt_sub
while arg[1] do
if arg[1] == "-i" or arg[1] == "--gameid" then
    opt_id = arg[2]
    if opt_id == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "-t" or arg[1] == "--gamename" then
    opt_title = arg[2]
    if opt_title == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "-d" or arg[1] == "--directory" then
    opt_directory = arg[2]
    if opt_directory == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "--raphnet" then
    opt_raphnet = true
    table.remove(arg, 1)
elseif arg[1] == "--disable-controller-remappings" then
    opt_disable_controller_remappings = true
    table.remove(arg, 1)
elseif arg[1] == "--no-trim" then
    opt_no_trim = true
    table.remove(arg, 1)
elseif arg[1] == "-m" then
    opt_rom = arg[2]
    if opt_rom == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "--mq-rom" then
    opt_mq_rom = arg[2]
    if opt_mq_rom == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "-o" then
    opt_out = arg[2]
    if opt_out == nil then usage() end
    table.remove(arg, 1)
    table.remove(arg, 1)
elseif arg[1] == "-s" then
    opt_sub = true
    table.remove(arg, 1)
elseif opt_iso ~= nil then usage()
else
    opt_iso = arg[1]
    table.remove(arg, 1)
end
end
if opt_iso == nil then usage() end

local gzinject = os.getenv("GZINJECT")
if gzinject == nil or gzinject == "" then gzinject = "gzinject" end

wiivc = true
require("lua/rom_table")
local make = loadfile("lua/make.lua")

-- extract iso
gru.os_rm(opt_directory)
local gzinject_cmd = gzinject ..
                    " -a extract" ..
                    " -d \"" .. opt_directory .. "\"" ..
                    " -s \"" .. opt_iso .. "\"" ..
                    " --verbose"
if opt_sub then gzinject_cmd = gzinject_cmd .. " 1>&2" end
local _,_,gzinject_result = os.execute(gzinject_cmd)
if gzinject_result ~= 0 then return gzinject_result end

-- check gc version
local gc_header = gru.blob_load(opt_directory .. "/header.bin")
local gc_version = gc_table[gc_header:crc32()]
if gc_version == nil then error("unrecognized gc version") end

-- check rom id
if opt_rom == nil then opt_rom = opt_directory .. "/" .. gc_version.rom_path end
local rom = gru.n64rom_load(opt_rom)
local rom_info = rom_table[rom:crc32()]
if rom_info == nil then
  io.stderr:write("patch-iso: unrecognized rom: " .. opt_rom .. "\n")
  return 2
end

-- patch rom
local patch = gru.ups_load("ups/" .. rom_info.gz_name .. ".ups")
patch:apply(rom)
rom:save_file(opt_directory .. "/" .. gc_version.rom_path)

-- patch MQ rom (if available)
if gc_version.mq_rom_path ~= nil then
if opt_mq_rom == nil then opt_mq_rom = opt_directory .. "/" .. gc_version.mq_rom_path end
local mq_rom = gru.n64rom_load(opt_mq_rom)
local mq_rom_info = rom_table[mq_rom:crc32()]
if mq_rom_info == nil then
  io.stderr:write("patch-iso: unrecognized mq rom: " .. opt_mq_rom .. "\n")
  return 2
end
local mq_patch = gru.ups_load("ups/" .. mq_rom_info.gz_name .. ".ups")
mq_patch:apply(mq_rom)
mq_rom:save_file(opt_directory .. "/" .. gc_version.mq_rom_path)
end

-- trim unnecessary files to save space
if not opt_no_trim then
  for _, trim_path in ipairs(gc_version.trim_paths) do
    gru.os_rm(opt_directory .. "/" .. trim_path)
  end
end

-- build gzinject pack command string
local gzinject_cmd = gzinject ..
                    " -a pack" ..
                    " -d \"" .. opt_directory .. "\"" ..
                    " --verbose"
if opt_id ~= nil then
gzinject_cmd = gzinject_cmd .. " -i \"" .. opt_id .. "\""
else
gzinject_cmd = gzinject_cmd .. " -i " .. rom_info.gc_game_id
end
if opt_title ~= nil then
gzinject_cmd = gzinject_cmd .. " -t \"" .. opt_title .. "\""
else
gzinject_cmd = gzinject_cmd .. " -t " .. rom_info.gz_name
end
gzinject_cmd = gzinject_cmd ..
                " -p \"gzi/homeboy/hb_" .. gc_version.game_id .. ".gzi\"" ..
                " --dol-iso-path \"" .. gc_version.dol_path .. "\"" ..
                " --dol-inject \"homeboy/bin/hb-" .. gc_version.game_id .. "/homeboy.bin\"" ..
                " --dol-loading 80300000"
if not opt_disable_controller_remappings then
if opt_raphnet then
    gzinject_cmd = gzinject_cmd .. " -p \"gzi/controller/gz_remap_raphnet_" .. gc_version.game_id .. ".gzi\""
else
    gzinject_cmd = gzinject_cmd .. " -p \"gzi/controller/gz_remap_default_" .. gc_version.game_id .. ".gzi\""
end
end
if opt_out ~= nil then
gzinject_cmd = gzinject_cmd .. " -s \"" .. opt_out .. "\""
elseif opt_title ~= nil then
gzinject_cmd = gzinject_cmd .. " -s \"" .. opt_title .. ".iso\""
else
gzinject_cmd = gzinject_cmd .. " -s \"" .. rom_info.gz_name .. ".iso\""
end
if opt_sub then gzinject_cmd = gzinject_cmd .. " 1>&2" end
-- execute
local _,_,gzinject_result = os.execute(gzinject_cmd)
if gzinject_result ~= 0 then return gzinject_result end

if opt_sub then print(rom_info.gz_name .. ".iso") end

return 0
