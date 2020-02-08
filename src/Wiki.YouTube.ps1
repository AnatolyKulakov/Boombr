﻿# Thanks:
# - https://lazywinadmin.com/2019/04/retrieving_youtube_videos_information_with_powershell.html

. $PSScriptRoot\Utility.ps1

$YouTubeApiEndpoint = 'https://www.googleapis.com/youtube/v3'
$VideoItemBatchSize = 50

function Group-ToStringBatch([int] $BatchSize = $VideoItemBatchSize, [string] $Separator = ',')
{
    begin
    {
        $items = @()
    }
    process
    {
        $items += $_
        if ($items.Count -ge $BatchSize)
        {
            $items -join $Separator
            $items = @()
        }
    }
    end
    {
        if ($items)
        {
            $items -join $Separator
            $items = @()
        }
    }
}

function Invoke-YouTubeMethod
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Resource,

        [Hashtable]
        $QueryParts = @{}
    )

    process
    {
        $QueryParts['key'] = 'YouTubeAccessToken' | Get-Secret
        $query = $QueryParts | Format-UriQuery

        $url = "${YouTubeApiEndpoint}/${Resource}?${query}"

        Invoke-RestMethod $url
    }
}

function Get-YouTubePlaylist
{
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ChannelId
    )

    process
    {
        $query = @{
            part = 'snippet'
            channelId = $ChannelId
            maxResults = $VideoItemBatchSize
        }

        $response = 'playlists' | Invoke-YouTubeMethod -QueryParts $query

        $response.items |
        ForEach-Object {
            $palylist = $_
            [PSCustomObject] @{
                PSTypeName = 'YouTubePlaylist'
                Id = $palylist.id
                Title = $palylist.snippet.title
            }
        }
    }
}

function Get-YouTubePlaylistItem
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [PSTypeName('YouTubePlaylist')]
        $Playlist
    )

    process
    {
        $next = $null

        do
        {
            $query = @{
                part = 'contentDetails'
                playlistId = $Playlist.Id
                maxResults = $VideoItemBatchSize
            }

            if ($next)
            {
                $query['pageToken'] = $next
            }

            $response = 'playlistItems' | Invoke-YouTubeMethod -QueryParts $query

            if ('nextPageToken' -in $response.PSObject.Properties.Name)
            {
                $next = $response.nextPageToken
            }
            else
            {
                $next = $null
            }

            $response.items |
            ForEach-Object {
                $palylistItem = $_
                $palylistItem.contentDetails.videoId
            }

        } while ($next)
    }
}

function Get-YouTubeVideo
{
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        $VideoId
    )

    begin
    {
        function ReadStatistic($value, [string] $Key)
        {
            if ($Key -in $value.statistics.PSObject.Properties.Name)
            {
                [int] $value.statistics.$Key
            }
            else
            {
                0
            }
        }
    }
    process
    {
        $query = @{
            part = 'snippet,statistics,contentDetails'
            id = $VideoId
            maxResults = $VideoItemBatchSize
        }

        $response = 'videos' | Invoke-YouTubeMethod -QueryParts $query

        $response.items |
        ForEach-Object {
            $video = $_

            [PSCustomObject] @{
                PSTypeName = 'YouTubeVideo'
                Id = $video.id
                Title = $video.snippet.title
                Duration = [Xml.XmlConvert]::ToTimeSpan($video.contentDetails.duration)
                ViewCount = ReadStatistic $video 'viewCount'
                LikeCount = ReadStatistic $video 'likeCount'
                DislikeCount = ReadStatistic $video 'dislikeCount'
                FavoriteCount = ReadStatistic $video 'favoriteCount'
                CommentCount = ReadStatistic $video 'commentCount'
            }
        }
    }
}
