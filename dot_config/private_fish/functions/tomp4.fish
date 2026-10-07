function tomp4 --description 'Re-encode a video to H.264/AAC .mp4, replacing it in place if it already is one'
    if test (count $argv) -ne 1
        echo "usage: tomp4 FILE" >&2
        return 2
    end
    set -l src $argv[1]
    if not test -f $src
        echo "tomp4: $src: no such file" >&2
        return 1
    end
    if not type -q ffmpeg
        echo "tomp4: ffmpeg not found" >&2
        return 1
    end

    set -l dst (path change-extension mp4 $src)
    # Encode next to the target first, so a failed run never clobbers anything
    # and an .mp4 source can be replaced in place.
    set -l tmp (path dirname $dst)/.(path basename $dst).tomp4-$fish_pid.mp4

    # yuv420p and even dimensions keep the result playable everywhere
    # (QuickTime, browsers, phones); faststart puts the index up front.
    ffmpeg -hide_banner -nostdin -i $src \
        -map 0:v:0 -map '0:a?' \
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
        -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
        -c:a aac -b:a 192k \
        -movflags +faststart -y $tmp
    or begin
        rm -f $tmp
        return 1
    end
    mv -f $tmp $dst
end
