local args = {...}

dfpwm = require('cc.audio.dfpwm')

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

local function safe_http(url, headers, binary)
    if headers == nil then 
        headers = nil
    end
    if binary == nil then 
        binary = false
    end

    local worked, http_error = http.checkURL(url)
    if worked == false then
        print('HTTP ERROR: '..http_error)
        return false, {}
    end
    
    local http_resp, http_error = http.get(url, headers, binary)
    if http_resp == nil then
        print('HTTP ERROR: '..http_error)
        return false, {}
    end
    return true, http_resp
end

local function get_playlist_info(playlist_url)
    local request_url = server_url .. 'read_videos?video_url=' .. url_encode(playlist_url)

    local worked, http_resp = safe_http(request_url)
    if worked == false then
        return nil
    end
    local videos = http_resp.readAll()
    http_resp.close()
    return textutils.unserializeJSON(videos)
end

local function get_next_url(playlist_url)
    local request_url = server_url .. 'next_url?video_url=' .. url_encode(playlist_url)

    local worked, http_resp = safe_http(request_url)
    if worked == false then
        return nil
    end
    local next_url = http_resp.readAll()
    http_resp.close()
    return textutils.unserializeJSON(next_url)
end

local function download_chunk(url, chunk_stuff, chunk_id)
    local request_url = server_url .. 'chunk_download?video_url=' .. url_encode(url) ..'&start_time='..chunk_stuff[1]..'&end_time='..chunk_stuff[2]

    local worked, http_resp = safe_http(request_url, nil, true)
    if worked == false then
        return nil
    end
    local dfpwm_data = http_resp.readAll()
    http_resp.close()
    return dfpwm_data
end

local function get_chunked_dur(video_details)
    local chunks = {}
    for chunk = 0, video_details['duration'], 15 do
        table.insert(chunks, {chunk, chunk+15})
    end
    return chunks
end

local function format_time(time, max_time)
    if max_time == nil then
        max_time = time
    end
    local hours = math.floor(time / 3600)
    local minutes = math.floor((time % 3600) / 60)
    local seconds = math.floor(time % 60)

    if max_time >= 3600 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    elseif max_time >= 60 then
        return string.format("%d:%02d", minutes, seconds)
    else
        return string.format("%d", seconds)
    end
end

width, height = term.getSize()
server_url = args[1]
paused = true
progress = 0.0
next_up = {args[2]}
current_video_url = args[2]
current_play_time = 0
last_chec_unix = os.clock()
duration = -1
changed = true
last_progress_printr = ''
audio_chunk_look_ups = {}
loaded_audio_chunks = {}
current_audio_chunk = 1
new_track = true

next_up = get_playlist_info(current_video_url)
audio_chunk_look_ups = get_chunked_dur(next_up[1])
current_audio_chunk = 1
duration = next_up[1]['duration']
current_play_time = 0


dfpwm_decoder = nil
speaker = peripheral.find("speaker")


local function update_loop()
    while true do
        local delta = os.clock()-last_chec_unix
        last_chec_unix = os.clock()

        -- only update progress while umpaused
        if paused == false then
            current_play_time = current_play_time + delta
            progress = current_play_time / duration
        end

        local progress_numbers = ' '..format_time(current_play_time, duration)..'/'..format_time(duration)
        local progress_bar_offset = #progress_numbers + 2
        local filled = math.floor(progress * (width - progress_bar_offset))
        local progress_print = '['..string.rep("\127", filled)..string.rep("\128", ((width-progress_bar_offset)-filled))..']'..progress_numbers


        -- update current video
        if current_play_time > duration then
            current_video_url = get_next_url(current_video_url)
            if current_video_url == nil then
                break
            end
            next_up = get_playlist_info(current_video_url)
            audio_chunk_look_ups = get_chunked_dur(next_up[1])
            current_audio_chunk = 1
            duration = next_up[1]['duration']
            current_play_time = 0
            new_track = true

        end

        if progress_print ~= last_progress_printr then
            changed = true
            last_progress_printr = progress_print
        end


        -- print('running')

        -- list_info = get_playlist_info(args[2])
        -- print(textutils.serialize(list_info))

        if changed == true then
            changed = false
            term.clear()
            term.setCursorPos(1, 1)
            print(filled, width, progress_bar_offset)
            print(progress_print)
            middle_symbol = paused and '\16' or '\124 \124'
            print(' <'..string.rep(' ', width/2-1)..middle_symbol..string.rep(' ', width/2-2-#middle_symbol)..'>')
            print(textutils.serialize(next_up))
            print(textutils.serialize(current_video_url))

        end


        if current_audio_chunk ~= 1 then
            loaded_audio_chunks[current_audio_chunk-1] = nil
        end

        if loaded_audio_chunks[current_audio_chunk] == nil then
            loaded_audio_chunks[current_audio_chunk] = download_chunk(next_up[1]['url'], audio_chunk_look_ups[current_audio_chunk], current_audio_chunk)
        end
        if current_audio_chunk < #audio_chunk_look_ups then
            if loaded_audio_chunks[current_audio_chunk+1] == nil then
                loaded_audio_chunks[current_audio_chunk+1] = download_chunk(next_up[1]['url'], audio_chunk_look_ups[current_audio_chunk+1], current_audio_chunk+1)
            end
        end
        current_audio_chunk = math.floor(current_play_time / 15) + 1    
        sleep(0.05)
    end
end

local function audio_loop()
    while true do
        sleep(0.05)
        if new_track == true then
            new_track = false
            dfpwm_decoder = dfpwm.make_decoder()
        end
        if paused == false then
            local decoded = decoder(loaded_audio_chunks[current_audio_chunk])
            while not speaker.playAudio(decoded) do
                os.pullEvent("speaker_audio_empty")
            end
        end
    end
end

local function key_loop()
    while true do
        sleep(0.1)
        local event, key, is_held = os.pullEvent("key")
        if key == string.byte(" ") then
            paused = not paused
        end
    end
end

parallel.waitForAny(audio_loop, update_loop, key_loop)
print('Done')