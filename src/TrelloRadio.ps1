#Requires -Version 5
#Requires -Modules PowerTrello

Set-StrictMode -version Latest
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\Utility.ps1
. $PSScriptRoot\YamlCuteSerialization.ps1
. $PSScriptRoot\Model.ps1
. $PSScriptRoot\Serialization.ps1

$TrelloBoardName = 'RadioDotNet'
$TrelloNewCardListName = 'Обсуждаем-'
$AuditDir = Join-Path $PSScriptRoot '..\..\Audit\db' -Resolve
$InformationPreference = 'Continue'

$EpisodeSorter = { @('Number', 'Title', 'PublishDate', 'Authors', 'Mastering', 'Music', 'Home', 'Audio', 'Topics', 'Subject', 'Timestamp', 'Links').IndexOf($_) }


class FormatString
{
    [bool] $AsHtml
    [Text.StringBuilder] $Writer

    FormatString([bool] $AsHtml)
    {
        $this.AsHtml = $AsHtml
        $this.Writer = New-Object -TypeName 'System.Text.StringBuilder'
    }

    [String] ToString()
    {
        return $this.Writer.ToString().Trim()
    }

    [string] Encode([string] $text)
    {
        if ($this.AsHtml)
        {
            return [System.Net.WebUtility]::HtmlEncode($text)
        }
        else
        {
            return $text
        }
    }

    [string] Wrap([string] $openTag, [string] $text, [string] $closeTag)
    {
        if ($this.AsHtml)
        {
            return $openTag + $text + $closeTag
        }
        else
        {
            return $text
        }
    }

    [string] Strong([string] $text)
    {
        return $this.Wrap('<strong>', $text, '</strong>')
    }

    static [string] GetTextByUrl([string] $url)
    {
        $uri = [Uri] $url
        $max = 42
        $tail = $uri.AbsolutePath

        # Remove lang segment
        $tail = $tail.Replace('/en-us/', '/').Replace('/ru-ru/', '/')
        # Remove date segment
        $tail = $tail -replace '/\d{4}/\d{2}/\d{2}/','/'
        # Remove short date segment
        $tail = $tail -replace '/\d{4}/\d{2}/','/'

        $tail = $tail.TrimEnd('/', '-')
        $tail = if ($tail.Length -le $max)
        {
            $tail
        }
        else
        {
            $suffix = '...'
            $tail.Substring(0, $max - $suffix.Length) + '...'
        }

        $authority = $uri.Authority
        # Remove www segment
        $authority = $authority.TrimStart('www.')

        return $authority + $tail
    }

    [string] Link([string] $url)
    {
        return $this.Link($url, $null)
    }

    [string] Link([string] $url, [string] $text)
    {
        $h = if ($this.AsHtml) { 'h' } else { '_' }
        $u = if ($url) { 'u' } else { '_' }
        $t = if ($text) { 't' } else { '_' }
        $mask = "$h$u$t"

        switch ($mask)
        {
            '__t' { return $text }
            '_u_' { return $url }
            '_ut' { return "$text ($url)" }
            'h_t' { return $text }
            'hu_' { return '<a href="{0}">{1}</a>' -f $url,[FormatString]::GetTextByUrl($url) }
            'hut' { return '<a href="{0}">{1}</a>' -f $url,$text }
            # '___'
            # 'h__'
        }

        throw 'Nothing'
    }

    BeginList()
    {
        $this.BeginList($null)
    }

    BeginList([string] $title)
    {
        if ($this.AsHtml)
        {
            if ($title)
            {
                $this.Paragraph($title)
            }

            $this.Writer.AppendLine('<ul>')
        }
        else
        {
            if ($title)
            {
                $this.Writer.AppendLine($title)
            }
        }
    }

    EndList()
    {
        if ($this.AsHtml)
        {
            $this.Writer.AppendLine('</ul>')
        }
        else
        {
            $this.Writer.AppendLine()
        }
    }

    ListItem([string] $text)
    {
        if ($this.AsHtml)
        {
            $format = "  <li>$text</li>"
        }
        else
        {
            $format = "• $text"
        }

        $this.Writer.AppendLine($format)
    }

    Paragraph([string] $text)
    {
        if ($this.AsHtml)
        {
            $format = "<p>$text</p>"
            $this.Writer.AppendLine($format)
        }
        else
        {
            $this.Writer.AppendLine($text)
            $this.Writer.AppendLine()
        }
    }
}


class PodcastAnnouncement
{
    static [string] $PodcastName = 'RadioDotNet'
    static [string] $SiteUrl = 'http://Radio.DotNet.Ru'
    static [string] $RssUrl = 'https://anchor.fm/s/f0c0ef4/podcast/rss'
    static [string] $VideoUrl = 'https://www.youtube.com/playlist?list=PLbxr_aGL4q3SpQ9GRn2jv-NEpvN23CUC5'
    static [string] $GoogleUrl = 'https://podcasts.google.com/feed/aHR0cHM6Ly9hbmNob3IuZm0vcy9mMGMwZWY0L3BvZGNhc3QvcnNz'
    static [string] $AppleUrl = 'https://podcasts.apple.com/us/podcast/radiodotnet/id1484348948'
    static [string] $YandexUrl = 'https://music.yandex.ru/album/12041961'

    [hashtable] $Podcast
    [hashtable] $Links
    [FormatString] $Report

    PodcastAnnouncement([hashtable] $Podcast)
    {
        $this.Init($Podcast, @{}, $false)
    }
    PodcastAnnouncement([hashtable] $Podcast, [hashtable] $Links)
    {
        $this.Init($Podcast, $Links, $false)
    }
    PodcastAnnouncement([hashtable] $Podcast, [hashtable] $Links, [bool] $AsHtml)
    {
        $this.Init($Podcast, $Links, $AsHtml)
    }

    hidden Init([hashtable] $Podcast, [hashtable] $Links, [bool] $AsHtml)
    {
        $this.Podcast = $Podcast
        $this.Links = $Links
        $this.Report = [FormatString]::new($AsHtml)
    }

    [String] ToString()
    {
        return $this.Report.ToString()
    }

    [string] FormatDate([string] $template)
    {
        $localPubDate = $this.Podcast['PublishDate'] | ConvertTo-LocalTime
        return $localPubDate.ToString($template, [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU'))
    }

    [PodcastAnnouncement] Identity()
    {
        $textPubDate = ''
        if ($this.Podcast.Contains('PublishDate'))
        {
            $textPubDate = $this.FormatDate(' от d MMMM yyyy года')
        }

        $text = "Подкаст $($this::PodcastName) выпуск №$($this.Podcast['Number'])$textPubDate"
        $format = $this.Report.Strong($this.Report.Encode($text))
        $this.Report.Paragraph($format)
        return $this
    }

    [PodcastAnnouncement] ShortDate()
    {
        $textPubDate = $this.FormatDate('d MMM yyyy')
        $this.Report.Paragraph($this.Report.Encode($textPubDate))
        return $this
    }

    [PodcastAnnouncement] Slogan()
    {
        $format = $this.Report.Encode('Разговоры на тему .NET во всех его проявлениях, новости, статьи, библиотеки, конференции, личности и прочее интересное из мира IT.')
        $this.Report.Paragraph($format)
        return $this
    }

    [PodcastAnnouncement] Description()
    {
        if ($this.Podcast.Contains('Description'))
        {
            # TODO: MarkDown to HTML (Para, Links)
            $format = $this.Report.Encode($this.Podcast['Description'])
            $this.Report.Paragraph($format)
        }

        return $this
    }

    [PodcastAnnouncement] Home()
    {
        $link = $this.Report.Link($this.Podcast['Home'])
        $this.Report.Paragraph($link)
        return $this
    }

    [PodcastAnnouncement] Audio()
    {
        $link = $this.Report.Link($this.Podcast['Audio'])
        $this.Report.Paragraph("Аудиоверсия: $link")
        return $this
    }

    [PodcastAnnouncement] Rss()
    {
        $link = $this.Report.Link($this::RssUrl)
        $this.Report.Paragraph("RSS подписка на подкаст: $link")
        return $this
    }

    [PodcastAnnouncement] PlayResources()
    {
        $link = $this.Report.Link($this::SiteUrl)
        $this.Report.Paragraph("Сайт: $link")
        $link = $this.Report.Link($this::GoogleUrl)
        $this.Report.Paragraph("Google Podcasts: $link")
        $link = $this.Report.Link($this::AppleUrl)
        $this.Report.Paragraph("Apple Podcasts: $link")
        $link = $this.Report.Link($this::YandexUrl)
        $this.Report.Paragraph("Яндекс Музыка: $link")
        $link = $this.Report.Link($this::VideoUrl)
        $this.Report.Paragraph("YouTube Playlist: $link")
        return $this
    }

    [PodcastAnnouncement] Site()
    {
        $link = $this.Report.Link($this::SiteUrl)
        $this.Report.Paragraph("Сайт подкаста: $link")
        return $this
    }

    [PodcastAnnouncement] Authors()
    {
        $this.Report.BeginList('Голоса выпуска:')

        foreach ($author in $this.Podcast['Authors'])
        {
            $link = $this.Links[$author]
            $text = $this.Report.Encode($author)
            $format = $this.Report.Link($link, $text)
            $this.Report.ListItem($format)
        }

        $this.Report.EndList()
        return $this
    }

    [PodcastAnnouncement] Mastering()
    {
        $mastering = $this.Podcast['Mastering']
        if ($mastering)
        {
            $link = $this.Links[$mastering]
            $text = $this.Report.Encode($mastering)
            $format = $this.Report.Link($link, $text)
            $this.Report.BeginList('Звукорежиссёр:')
            $this.Report.ListItem($format)
            $this.Report.EndList()
        }
        return $this
    }

    [PodcastAnnouncement] Music()
    {
        $music = $this.Podcast['Music']
        if ($music)
        {
            foreach ($name in $music.Keys)
            {
                $link = $music[$name]
                $text = $this.Report.Encode($name)
                $format = $this.Report.Link($link, $text)
                $this.Report.BeginList('Фоновая музыка:')
                $this.Report.ListItem($format)
                $this.Report.EndList()
            }
        }
        return $this
    }

    [PodcastAnnouncement] Topics()
    {
        return $this.Topics($true)
    }

    [PodcastAnnouncement] Topics([bool] $IncludeLinks)
    {
        $formatTitle = $this.Report.Strong('Темы:')
        $this.Report.Paragraph($formatTitle)

        foreach ($topic in $this.Podcast['Topics'])
        {
            $formatTopic = $this.Report.Encode("[$($topic.Timestamp)] — $($topic.Subject)")
            if ($IncludeLinks)
            {
                $this.Report.BeginList($formatTopic)
                foreach ($link in $topic.Links)
                {
                    $formatLink = $this.Report.Link($link)
                    $this.Report.ListItem($formatLink)
                }
                $this.Report.EndList()
            }
            else
            {
                $this.Report.Paragraph($formatTopic)
            }
        }

        return $this
    }

    [PodcastAnnouncement] Tags()
    {
        $text = $this.Report.Encode('#Podcast #DotNet')
        $this.Report.Paragraph($text)
        return $this
    }
}


function Select-EpisodeNumber
{
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $EpisodeId
    )

    process
    {
        if ($EpisodeId -match '\w+-(?<number>\d+)')
        {
            return [int]$Matches['number']
        }

        throw "Can't extract episode number from «$EpisodeId»"
    }
}

function Format-PodcastHeader
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [int] $EpisodeNumber
    )

    process
    {
        @{
            Number = $EpisodeNumber
            Title = "$([PodcastAnnouncement]::PodcastName) №${EpisodeNumber}"
            Authors = @('Анатолий Кулаков', 'Игорь Лабутин')
            Mastering = 'Максим Шошин'
            Music = @{ 'Максим Аршинов «Pensive yeti.0.1»' = 'https://hightech.group/ru/about' }
        }
    }
}

function Format-PodcastTopic
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [object] $Card
    )

    begin
    {
        $topicCount = 0
        $linkCount = 0
    }
    process
    {
        $subject = $Card.name.Trim()
        Write-Information "- $subject"

        [string[]] $links = $Card.desc -split "`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^https?://' }

        @{
            Subject = $subject
            Timestamp = '00:00:00'
            Links = $links
        }

        $topicCount++
        $linkCount += $links.Count
    }
    end
    {
        Write-Information "Found: $topicCount topics, $linkCount links"
    }
}

function ConvertTo-RssPodcastItem
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Xml.XmlElement] $RssItem
    )

    process
    {
        $title = $RssItem.title.'#cdata-section'.Trim()
        @{
            Number = $title | Select-EpisodeNumber
            Title = $title
            PublishDate = [datetime]$RssItem.pubDate
            Home = $RssItem.link.Trim()
            Audio = $RssItem.enclosure.url.Trim()
            AudioLength = $RssItem.enclosure.length.Trim()
        }
    }
}

function Format-PodcastRssHeader
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast
    )

    process
    {
        $rssItem = Invoke-RestMethod -Method Get -Uri ([PodcastAnnouncement]::RssUrl) |
            ConvertTo-RssPodcastItem |
            Where-Object { $_['Number'] -eq $Podcast['Number'] }

        if (-not $rssItem)
        {
            return
        }

        $Podcast['PublishDate'] = $rssItem['PublishDate']
        $Podcast['Home'] = $rssItem['Home']
        $Podcast['Audio'] = $rssItem['Audio']

        $Podcast
    }
}

function ConvertTo-PodcastMarkDowm
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast
    )

    process
    {
        $description = ''
        if ($Podcast.Contains('Description'))
        {
            $description = $Podcast['Description']
            $podcast.Remove('Description')
        }
        '---'
        ConvertTo-CuteYaml -Data $Podcast -KeyOrderer $EpisodeSorter
        '---'
        $description.Trim()
    }
}

function ConvertFrom-PodcastMarkDowm
{
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $Line
    )

    begin
    {
        $yaml = ''
        $frontMatter = $false
        $frontMatterSplitter = '---'
        $markdown = ''
        $nl = [System.Environment]::NewLine
    }
    process
    {
        if ($frontMatter)
        {
            if ($Line -eq $frontMatterSplitter)
            {
                $frontMatter = $false
            }
            else
            {
                $yaml += $Line + $nl
            }
        }
        else
        {
            if ($Line -eq $frontMatterSplitter)
            {
                $frontMatter = $true
            }
            else
            {
                $markdown += $Line + $nl
            }
        }
    }
    end
    {
        $podcast = $yaml | ConvertFrom-Yaml
        $markdown = $markdown.Trim()
        if ($markdown)
        {
            $podcast['Description'] = $markdown
        }

        $podcast
    }
}

function Read-PersonLink
{
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AuditPath
    )

    process
    {
        Read-Speaker -AuditDir $AuditPath |
            Where-Object { $_.TwitterUrl } |
            ConvertTo-Hashtable { $_.Name } { $_.TwitterUrl }
    }
}

function Format-AnchorAnnouncement
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast
    )

    process
    {
        [PodcastAnnouncement]::new($Podcast, @{}, $true).
            Identity().
            Description().
            Site().
            Topics().
            Music().
            ToString()
    }
}

function Format-VKAnnouncement
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast,

        [Parameter(Mandatory)]
        [hashtable]
        $Links
    )

    process
    {
        [PodcastAnnouncement]::new($Podcast, $Links).
            Identity().
            Home().
            Description().
            Site().
            Rss().
            Topics().
            Authors().
            Mastering().
            Music().
            PlayResources().
            Tags().
            ToString()
    }
}

function Format-YouTubeAnnouncement
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast,

        [Parameter(Mandatory)]
        [hashtable]
        $Links
    )

    process
    {
        [PodcastAnnouncement]::new($Podcast, $Links).
            Identity().
            Slogan().
            Description().
            Audio().
            Topics().
            Authors().
            Mastering().
            Music().
            Site().
            PlayResources().
            Tags().
            ToString()
    }
}

function Format-PodcastCover
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast,

        [Parameter(Mandatory)]
        [string]
        $PodcastHome
    )

    process
    {
        [PodcastAnnouncement]::new($Podcast, @{}).
            Identity().
            ShortDate().
            Topics($false).
            ToString()

        $coverPath = Join-Path $PodcastHome 'cover.svg'
        ''
        "$coverPath"
        'PNG: 1920 × 1080'
        'https://www.headliner.app/'
        'Rss: https://anchor.fm/s/f0c0ef4/podcast/rss'
    }
}

function Set-PodcastToFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $Podcast
    )

    process
    {
        ConvertTo-PodcastMarkDowm -Podcast $podcast |
        Set-Content -Path $Path -Encoding UTF8
    }
}

function Get-PodcastFromFile
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process
    {
        Get-Content -Path $Path -Encoding UTF8 |
        ConvertFrom-PodcastMarkDowm
    }
}

function New-PodcastFromTrello
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process
    {
        $timer = Start-TimeOperation -Name 'Create podcast from Trello'

        $board = Get-TrelloBoard -Name $TrelloBoardName
        if (-not $board) { throw "Trello board «$TrelloBoardName» not found" }

        $list = $board | Get-TrelloList | Where-Object { $_.name.StartsWith($TrelloNewCardListName) }
        if (-not $list) { throw "Trello list «$TrelloNewCardListName» in board «$TrelloBoardName» not found" }

        $episodeNumber = $list.name | Select-EpisodeNumber

        $dirName = Join-Path -Path $Path ('{0:D3}' -f $episodeNumber)
        New-Item -Path $dirName -ItemType Directory | Out-Null

        $filePath = Join-Path -Path $dirName 'index.md'

        Write-Information "Scan «$($list.name)» list in «$($board.name)» board for episode №$episodeNumber"

        $podcast = $episodeNumber | Format-PodcastHeader
        $podcast['Topics'] = $board |
             Get-TrelloCard -List $list |
             Format-PodcastTopic

        $filePath | Set-PodcastToFile -Podcast $podcast

        $timer | Stop-TimeOperation

        Write-Information "Please, fill in Authors, Description and Timestamps before the next step in «$(Split-Path -Leaf $filePath)»"
    }
}

function New-PodcastAnnouncementForAnchor
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "Index file «$Path» not found" }

        Write-Information "Format Anchor announcement from «$Path»"

        $podcast = Get-PodcastFromFile -Path $Path
        $podcastHome = Split-Path $Path

        Format-AnchorAnnouncement -Podcast $podcast |
        Set-Content -Path ([IO.Path]::ChangeExtension($Path, 'anchor.html')) -Encoding UTF8

        # TODO: Format SVG cover
        Format-PodcastCover -Podcast $podcast -PodcastHome $podcastHome |
        Set-Content -Path ([IO.Path]::ChangeExtension($Path, 'cover.txt')) -Encoding UTF8
    }
}

function New-PodcastFromAchor
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "Index file «$Path» not found" }

        $podcast = Get-PodcastFromFile -Path $Path

        $episodeNumber = $podcast.Number
        Write-Information "Enrich episode №$episodeNumber"

        $podcast = Format-PodcastRssHeader -Podcast $podcast

        if (-not $podcast)
        {
            Write-Warning "Can't found episode №$episodeNumber in RSS feed"
            return
        }

        $uniqSuffix = Get-Date -Format 'mmssfffffff'
        Copy-Item -Path $Path -Destination ([IO.Path]::ChangeExtension($Path, "${uniqSuffix}.bak")) -Force | Out-Null

        $Path | Set-PodcastToFile -Podcast $podcast
    }
}

function New-PodcastAnnouncement
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "Index file «$Path» not found" }

        Write-Information "Format announcements from «$($Path)»"

        $podcast = Get-PodcastFromFile -Path $Path
        $links = Read-PersonLink -AuditPath $AuditDir

        Format-YouTubeAnnouncement -Podcast $podcast -Links $links |
        Set-Content -Path ([IO.Path]::ChangeExtension($Path, 'youtube.txt')) -Encoding UTF8

        Format-VKAnnouncement -Podcast $podcast -Links $links |
        Set-Content -Path ([IO.Path]::ChangeExtension($Path, 'vk.txt')) -Encoding UTF8
    }
}

# $PodcastHome = Join-Path $PSScriptRoot '..\..\Site\input\Radio' -Resolve
# $PodcastIndex = Join-Path $PodcastHome '000' | Join-Path -ChildPath 'index.md'

# Step 1
# Get-TrelloConfiguration | Out-Null
# $PodcastHome | New-PodcastFromTrello

# Step 2
# New-PodcastAnnouncementForAnchor -Path $PodcastIndex

# Step 3
# New-PodcastFromAchor -Path $PodcastIndex

# Step 4
# New-PodcastAnnouncement -Path $PodcastIndex
# - VK/DotNetRu
# - Tg/DotNetRu
# - Tw/DotNetRu
# - YT/DotNetRu
