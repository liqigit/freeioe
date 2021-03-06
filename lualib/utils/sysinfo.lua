--- Helper functions for getting system information
-- @author Dirk Chang
--

local skynet = require 'skynet'

local _M = {}


--- Get output of shell command
--
_M.exec = function(cmd, inplace)
	local cmd = cmd..' 2>/dev/null'
	if true or inplace then
		local f, err = io.popen(cmd)
		if not f then
			return nil, err
		end
		local s = f:read('*a')
		f:close()
		return s
	else
		return skynet.call(".exec_sal", "lua", "exec", cmd)
	end
end

_M.cat_file = function(path)
	local f, err = io.open(path, 'r')
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s
end

--- Get the cpu model
-- @treturn string CPU Model 
_M.cpu_model = function()
	local s, err = _M.cat_file('/proc/cpuinfo')
	if not s then
		return "Unknown"
	end
	--return s:match("Hardware%s+:%s+([^%c]+)")
	return s:match("model%s+name%s*:%s*([^%c]+)") or s:match("system%s+type%s*:%s*([^%c]+)") or 'Unknown'
end

local try_read_cpu_temp_by_sysinfo = function()
	local s, err = _M.exec('sysinfo temp', true)
	if s and string.len(s) > 0 then
		local temp = tonumber(string.match(s, 'current:%s-(%d+)'))
		if temp then
			return temp / 1000
		end
	end
end

--- Get the cpu temperature
-- @treturn number CPU Temperature
_M.cpu_temperature = function()
	local temp = try_read_cpu_temp_by_sysinfo()
	if temp then
		return temp
	end
	return nil, "Cannot read cpu temperature"
end

--- Get the output for uname
-- @tparam string arg The args for uname command. e.g. -a -A -u
-- @treturn string the output from uname
_M.uname = function(arg)
	local cmd = 'uname '..arg
	local s, err = _M.exec(cmd, true)
	if not s then
		return nil, err
	end

	s = string.gsub(s, "\n", "")

	return s
end

local function proc_mem_info()
	local s, err = _M.cat_file('/proc/meminfo')
	if not s then
		return nil, err
	end

	local total = s:match("MemTotal:%s-(%d+)")
	local free = s:match("MemFree:%s-(%d+)")
	local used = total - free

	return {total = total, used = used, free=free}
end

--- Get the memory information
-- includes 'total' 'used' 'free'
-- @treturn table information struct {total=xx, used=xx, free=xx}
_M.meminfo = function()
	local s, err = _M.exec('free', true)
	if not s then
		return nil, err
	end

	local info = s:gmatch("Mem:%s-(%d+)%s-(%d+)%s-(%d+)")
	local total, used, free = info()
	if total then
		return { total = total, used = used, free = free }
	else
		return proc_mem_info()
	end
end

--- Get the system uptime
-- includes 'total' 'used' 'free'
-- @treturn table information struct {total=xx, used=xx, free=xx}
_M.uptime = function()
	local s, err = _M.cat_file('/proc/uptime')
	if not s then
		return nil, err
	end

	return string.match(s, "([%d%.]+)%s")
end

--- Get he loadavg
-- output the loadavg as one table, includes: lavg_1, lavg_5, lavg_15, nr_running, nr_threads, last_pid
-- @treturn table Refer to description
_M.loadavg = function()
	local s, err = _M.cat_file('/proc/loadavg')
	if not s then
		return nil, err
	end

	-- Find the idle times in the stdout output
	local tokens = s:gmatch('%s-([%d%.]+)')

	local avgs = {}
	for w in tokens do
		avgs[#avgs + 1] = w
	end
	local unpack = table.unpack or unpack
	local lavg_1, lavg_5, lavg_15, nr_running, nr_threads, last_pid = unpack(avgs)
	return {
		lavg_1 = lavg_1,
		lavg_5 = lavg_5,
		lavg_15 = lavg_15,
		nr_running = nr_running,
		nr_threads = nr_threads,
		last_pid = last_pid
	}
end

--- Get the network information
-- @tparam string ifname The interface name
-- @treturn table
local function network_if(ifname)
	local patt = '%g'
	if _VERSION == 'Lua 5.1' then
		patt = '[^%s]'
	end

	local s, err = _M.exec('PATH=$PATH:/sbin LANG=C ifconfig '..ifname, true)
	if not s then
		return nil, err
	end

	local hwaddr = s:match('HWaddr%s-('..patt..'+)') or s:match('ether%s-('..patt..'+)')
	if not hwaddr then
		return nil, "Cannot get correct MAC address from "..ifname
	end
	local ipv4 = s:match('inet%s+addr:%s-('..patt..'+)') or s:match('inet%s-('..patt..'+)')
	local ipv6 = s:match('inet6%s+addr:%s-('..patt..'+)') or s:match('inet6%s-('..patt..'+)')
	return {hwaddr=hwaddr, ipv4 = ipv4, ipv6=ipv6}
end

_M.network_if = network_if

--- List all network interfaces
-- @treturn table Includes all network information
_M.network = function()
	local patt = '[%g^:]'
	if _VERSION == 'Lua 5.1' then
		patt = '[^%s:]'
	end

	local s, err = _M.cat_file('/proc/net/dev')
	if not s then
		return nil, err
	end

	local tokens = s:gmatch('%s-('..patt..'+):')
	local ifs = {}
	for w in tokens do
		if w ~= 'lo' then
			ifs[#ifs + 1] = w
		end
	end
	local info = {}
	for k, v in pairs(ifs) do
		info[v] = network_if(v)
	end
	return info;
end

_M.list_serial = function()
	local f = io.popen('ls /dev/ttyS* /dev/ttyUSB* /dev/ttyACM*')
	if not f then
		return nil, err
	end

	local list = {}
	for line in f:lines() do
		local name = line:match('^(/dev/tty.+)$')
		list[#list + 1] = name
	end

	f:close()

	return list
end

local function get_versions(fn)
	local f, err = io.open(fn, "r")
	if not f then
		return 0, "develop"
	end
	local v = tonumber(f:read("l"))
	local gv = f:read("l")
	f:close()
	return v, gv
end

_M.version = function()
	local v, gv = get_versions("./ioe/version")
	return v, gv
end

_M.skynet_version = function()
	local v, gv = get_versions("./version")
	return v, gv
end

local arch_short_names = {
	['arm_cortex-a9_neon'] = 'arm', -- openwrt imx6
	armv5tejl = 'arm', --mx0
	armv7l = 'arm', --imx6
	x86_64 = 'x86_64',
	mips = 'mips',
}

-- for detecting cpu arch short name. when calling binrary built by go-lang
_M.cpu_arch_short = function(os_id)
	local arch = _M.cpu_arch(os_id)
	return arch_short_names[arch] or arch
end

---
-- for detecting cpu arch
_M.cpu_arch = function(os_id)
	local os_id = os_id or _M.os_id()
	if os_id == 'openwrt' then
		return _M.openwrt_cpu_arch()
	end
	local matchine_arch = _M.uname('-m')
	return assert(matchine_arch or os.getenv("IOE_CPU_ARCH"))
end

local function read_openwrt_arch()
	local f, err = io.open('/etc/os-release', 'r')
	if not f then
		return nil, 'os-release file does not exits'
	end
	for l in f:lines() do
		local id = string.match(l, '^LEDE_ARCH="*(.-)"*$') or string.match(l, '^OPENWRT_ARCH="*(.-)"*$')
		if id then
			f:close()
			return id
		end
	end
	f:close()
	return nil, 'os-release file does not contains LEDE_ARCH'
end

_M.openwrt_cpu_arch = function()
	return assert(read_openwrt_arch() or os.getenv("IOE_CPU_ARCH"))
end

local function read_os_id()
	local f, err = io.open('/etc/os-release', 'r')
	if not f then
		return nil, 'os-release file does not exits'
	end
	for l in f:lines() do
		local id = string.match(l, '^ID="*(.-)"*$')
		if id then
			f:close()
			return id
		end
	end
	f:close()
	return nil, 'os-release file does not contains ID'
end

local os_id_names = {
	debian = 'linux',
	ubuntu = 'linux',
	lede = 'openwrt',
}

_M.os_id = function()
	local os_id = read_os_id()
	os_id = os_id_names[os_id] or os_id
	return assert(os_id or os.getenv("MSYSTEM"))
end

_M.platform = function()
	local os_id = _M.os_id()
	local arch = _M.cpu_arch(os_id)
	return os_id.."/"..arch
end

local device_types_names = {
	armv5tejl = 'mx0',
	armv7l = 'q102',
	x86_64 = 'x86_64',
	mips = 'tp-720n',
}

_M.device_type = function()
	local uname = _M.uname('-m')
	return assert(device_types_names[uname] or os.getenv("IOE_DEVICE_TYPE"))
end

local try_read_ioe_sn_from_config = function()
	local f, err = io.open("/sbin/uci", "r")
	if f then
		--- This is openwrt system
		f:close()
		local s, err = _M.exec('uci get ioe.@system[0].sn', true)
		if s and string.len(s) > 0 then
			if string.sub(s, -1) == "\n" then
				return string.sub(s, 1, -2)
			end
			return s
		end
	else
		local f, err = io.open("/etc/ioe.ini")
		if f then
			local inifile = require 'inifile'
			local data, err = inifile.parse("/etc/ioe.ini")
			f:close()
			if data and data.system then
				return data.system.sn
			end
		end
	end
end

local try_gen_ioe_sn_by_mac_addr = function()
	local ndi = network_if('eth0') or network_if('br-lan') or network_if('wan')
	if ndi and ndi.hwaddr then
		return string.upper(string.gsub(ndi.hwaddr, ':', ''))
	end
end

local try_read_ioe_sn_by_sysinfo = function()
	local s, err = _M.exec('sysinfo psn', true)
	if s and string.len(s) > 0 then
		local patt = '%g'
		if _VERSION == 'Lua 5.1' then
			patt = '[^%s]'
		end
		return string.match(s, "PSN:%s+("..patt.."+)")
	end
end

--- Buffer the sn
local _ioe_sn = nil
local read_ioe_sn = function()
	if _ioe_sn then
		return _ioe_sn
	end
	-- TODO: for device sn api
	_ioe_sn = try_read_ioe_sn_from_config() or try_read_ioe_sn_by_sysinfo()
	if not _ioe_sn then
		_ioe_sn = try_gen_ioe_sn_by_mac_addr() or _M.unknown_ioe_sn
	end
	return _ioe_sn
end

_M.unknown_ioe_sn = "UNKNOWN_ID"
_M.ioe_sn = function()
	return assert(read_ioe_sn() or os.getenv("IOE_SN"))
end

_M.firmware_version = function()
	local s, err = _M.exec('sysinfo sw', true)
	if s and string.len(s) > 0 then
		local patt = '%g'
		if _VERSION == 'Lua 5.1' then
			patt = '[^%s]'
		end
		return string.match(s, "Firmware Version:%s+("..patt.."+)")
	else
		local s, err = _M.cat_file('/etc/os-release')
		if s then
			return string.match(s, 'PRETTY_NAME="([^"]+)"')
		end
	end
end

return _M
