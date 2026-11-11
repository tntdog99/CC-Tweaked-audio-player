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
    local request_url = server_url .. 'read_videos?video_url=' .. url_encode(playlist_url)
    print(http.checkURL(request_url))
    http_resp, error = http.get(request_url)
    videos = http_resp.readAll()
    return videos
end

local function format_time(time, max_time)
    formatted_time = ''
    if max_time == nil then
        max_time = time
    end
    local hours = math.floor(time / 3600)
    local minutes = math.floor((time % 3600) / 60)
    local seconds = math.floor(time % 60)

    local max_hours = math.floor(time / 3600)
    local max_minutes = math.floor((time % 3600) / 60)
    local max_seconds = math.floor(time % 60)

    if max_hours > 1 then
        formatted_time = formatted_time..hours..':'
    end
    if max_minutes > 1 then
        formatted_time = formatted_time..minutes..':'
    end
    if max_seconds > 1 then
        formatted_time = formatted_time..seconds..':'
    end
    return formatted_time
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

    local progress_numbers = format_time(current_play_time, duration)..'/'..format_time(duration)
    local progress_bar_offset = #progress_numbers + 2
    local filled = math.floor(progress * (width - progress_bar_offset))




    if filled ~= last_fill_progress_bar then
        changed = true
        last_fill_progress_bar = filled
    end


    -- print('running')

    -- list_info = get_playlist_info(args[2])
    -- print(textutils.serialize(list_info))

    if changed == true then
        changed = false
        term.clear()
        term.setCursorPos(1, 1)
        print(filled, width, progress_bar_offset)
        print('['..string.rep("\127", filled)..string.rep("\128", ((width-progress_bar_offset)-filled))..']'..progress_numbers)
    end
    sleep(0.1)
end