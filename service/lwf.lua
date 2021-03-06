local skynet = require "skynet"
local socket = require "skynet.socket"
local co_m = require "skynet.coroutine"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string

local option_web = true

local mode = ...

if mode == "agent" then

local cache = require 'skynet.codecache'
local log = require 'utils.log'

local function response(id, ...)
	local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		skynet.error(string.format("fd = %d, %s", id, err))
	end
end

skynet.start(function()
	--cache.mode('EXIST')

	local lwf_skynet = require 'lwf.skynet.init'
	local lwf_skynet_assets = require 'lwf.skynet.assets'
	local lwf_root = SERVICE_PATH.."/../www"
	--local lwf_root = "/home/cch/mycode/lwf/example"
	local lwf = require('lwf').new(lwf_root, lwf_skynet, lwf_skynet_assets, co_m)

	local processing = nil
	skynet.dispatch("lua", function (_,_,id)
		while processing do
			local ts = skynet.now() - processing
			if ts > 500 then
				log.trace('::LWF:: Web process timeout', processing, skynet.now())
				break
			end
			skynet.sleep(20)
		end
		processing = skynet.now()
		socket.start(id)

		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body, httpver = httpd.read_request(sockethelper.readfunc(id), 4096 * 1024)
		log.trace('::LWF:: Web access', httpver, method, url, code)
		if code then
			if code ~= 200 then
				response(id, code)
			else
				local r, err = xpcall(lwf, debug.traceback, method, url, header, body, httpver, id, response)
				if not r then
					response(id, 500, err)
				end
			end
		else
			if url == sockethelper.socket_error then
				--skynet.error("socket closed")
			else
				skynet.error(url)
			end
		end
		socket.close(id)
		skynet.sleep(0)
		processing = nil
	end)
end)

else
local arg = table.pack(...)
assert(arg.n <= 2)

skynet.start(function()
	local ip = (arg.n == 2 and arg[1] or "0.0.0.0")
	local port = tonumber(arg[arg.n] or 8080)

	if option_web then
		local lfs = require 'lfs'
		if not lfs.attributes(lfs.currentdir().."/ioe/www", "mode") then
			skynet.error("Web not detected, web server closed!!")
			skynet.exit()
		end
	end

	local agent = {}
	for i= 1, 2 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent")
	end
	local balance = 1
	local id = socket.listen(ip, port)
	skynet.error("Web listen on:", ip, port)
	socket.start(id , function(id, addr)
		--skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
		skynet.send(agent[balance], "lua", id)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
end)

end
