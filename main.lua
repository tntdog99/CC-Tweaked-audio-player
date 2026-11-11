local args = {...}
local function url_encode(str)
    if str == nil then
        return ""
    end

    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return str
end

local function get_playlist_info(playlist_url)
    request_url = server_url .. 'read_videos?video_url=' .. url_encode(playlist_url)
    print(http.checkURL(request_url))
    http_resp, error = http.get(request_url)
    videos = http_resp.read()
    print(textutils.serialize(videos))
end

server_url = args[1]


print('running')
get_playlist_info(args[2])