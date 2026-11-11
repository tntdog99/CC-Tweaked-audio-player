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
    videos = http_resp.readAll()
    return videos
end


width, height = term.getSize()
server_url = args[1]
paused = true
progress = 0.0
next_up = {}
current_video_url = ''
current_play_time = 0
last_chec_unix = os.clock()
duration = 350
changed = true
last_fill_progress_bar = -1

while true do
    delta = os.clock()-last_chec_unix
    last_chec_unix = os.clock()
    current_play_time = current_play_time + delta
    progress = current_play_time / duration
    local filled = math.floor((progress/width))-2
    if filled ~= last_fill_progress_bar then
        changed = true
        last_fill_progress_bar = filled
    end


    -- print('running')

    -- list_info = get_playlist_info(args[2])
    -- print(textutils.serialize(list_info))

    if changed == true then
        print(filled, width)
        changed = false
        term.clear()
        term.setCursorPos(1, 1)
        print('['..string.rep("\128", filled)..string.rep("\127", (width-filled))..']')
    end
    sleep(0.1)
end