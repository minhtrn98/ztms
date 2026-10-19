# Free-text search over menu entries, used by Show-GroupedMenu's type-to-search
# (ProjectMenu.psm1) and by ztms.ps1's "did you mean" suggestions for an
# unknown direct-run target.
#
# Ranks entries by their DisplayName, group Name, Desc and Path. "Semantic"
# the cheap, offline way: query words go through concept groups of synonyms
# (English + Vietnamese, accents optional), so "tắt service" finds
# "stop-all — Stop all running backend services" and "kéo db dev" finds the
# dev database clone — no model, no network, instant on every keystroke.
#
# To make an entry easier to find, improve its Desc in ztms.ps1 first; add a
# word to $script:Concepts only when it's a general synonym that will help
# other entries too.

# Each line is one concept ("|"-separated): any word/phrase in it also matches the others.
# A word may sit in several concepts ("kéo" = git pull and = copy data down).
$script:Concepts = @(
    "stop | kill | shutdown | tắt | dừng | ngừng | ngắt"
    "start | run | launch | boot | chạy | bật | khởi động | mở"
    "restart | reload | khởi động lại | chạy lại"
    "open | show | mở | xem"
    "pull | fetch | git | kéo | kéo code | lấy code | cập nhật code | update code"
    "branch | checkout | switch | nhánh | chuyển nhánh | đổi nhánh"
    "vscode | vs code | code | editor | ide"
    "visual studio | studio | sln | solution | devenv"
    "folder | explorer | directory | thư mục"
    "publish | build | deploy | release | compile | triển khai | đóng gói | biên dịch"
    "backend | be | api | service | dotnet | net | dịch vụ"
    "frontend | fe | web | ui | next | nextjs | react | yarn | giao diện"
    "clone | sync | copy | dump | download | pull | kéo | kéo dữ liệu | lấy dữ liệu | đồng bộ | sao chép | tải | tải về"
    "restore | reapply | re apply | khôi phục | phục hồi | nạp lại"
    "database | db | postgres | postgresql | pg | sql | data | cơ sở dữ liệu | csdl | dữ liệu"
    "redis | cache | bộ nhớ đệm"
    "dev | development"
    "stg | staging"
    "android | emulator | avd | phone | mobile | app | apk | giả lập | máy ảo | điện thoại"
    "location | gps | geo | lat | lng | coordinates | post office | map | vị trí | tọa độ | toạ độ | bưu cục | bản đồ"
    "install | setup | cài | cài đặt | thiết lập"
    "uninstall | remove | delete | gỡ | gỡ cài đặt | xóa | xoá"
    "latest | newest | mới nhất | bản mới"
    "update | upgrade | cập nhật | nâng cấp"
    "config | configuration | settings | init | cấu hình | thiết lập"
    "env | environment | secret | secrets | password | key | biến môi trường | mật khẩu"
    "export | backup | sao lưu | xuất"
    "import | migrate | new machine | nhập | máy mới | chuyển máy"
    "doctor | check | diagnose | health | missing | kiểm tra | chẩn đoán | thiếu"
    "hotkey | shortcut | ctrl space | spotlight | phím tắt"
    "httptoolkit | http toolkit | htk | proxy | intercept | network | request | bắt request | mạng"
    "pms | postal | bưu chính"
    "cold | cold boot | snapshot | fresh | clean | default | sạch | mặc định"
    "all | every | tất cả | toàn bộ | hết"
)

$script:Inflections = @("s", "es", "d", "ed", "ing", "er", "ers")

# Filler words dropped from the query (unless it's the word still being typed)
$script:StopWords = @(
    "the", "a", "an", "to", "of", "for", "from", "and", "in", "on", "my", "me", "please", "i", "want",
    "ve", "cua", "cho", "cac", "nhung", "voi", "la", "len", "di", "giup", "muon", "minh", "toi", "cai", "nao", "hay", "thi", "de", "vao", "nhe", "luon", "bang"
)

function ConvertTo-MenuSearchText {
    # Lowercase, strip Vietnamese accents (đ -> d), punctuation -> spaces.
    # Regex, not a per-char loop: this runs ~160 times per keystroke and on
    # every concept phrase, and PowerShell loops are slow.
    param([string]$Text)
    if (-not $Text) { return "" }
    $decomposed = $Text.ToLowerInvariant().Replace('đ', 'd').Normalize([Text.NormalizationForm]::FormD)
    $script:NonAlnum.Replace($script:Accents.Replace($decomposed, ''), ' ').Trim()
}
$script:Accents = [regex]::new('\p{Mn}+')
$script:NonAlnum = [regex]::new('[^a-z0-9]+')

# phrase -> every phrase it's interchangeable with (across all its
# concepts). Built on the first search, not at import: importing happens on
# every ztms start (before the menu shows), while the first search only
# happens once the menu is up and waiting for a key.
$script:Alternatives = $null
$script:MaxPhraseWords = 1

function Initialize-MenuSearchConcepts {
    if ($null -ne $script:Alternatives) { return }
    $alternatives = @{}
    foreach ($concept in $script:Concepts) {
        $phrases = [Collections.Generic.HashSet[string]]::new()
        foreach ($raw in $concept.Split('|')) {
            $p = ConvertTo-MenuSearchText $raw
            if ($p) { [void]$phrases.Add($p) }
        }
        foreach ($p in $phrases) {
            if (-not $alternatives.ContainsKey($p)) { $alternatives[$p] = [Collections.Generic.HashSet[string]]::new() }
            $alternatives[$p].UnionWith($phrases)
            $script:MaxPhraseWords = [Math]::Max($script:MaxPhraseWords, $p.Split(' ').Count)
        }
    }
    $script:Alternatives = $alternatives
}

function Get-MenuSearchTerms {
    # Query -> terms, each { Literal; Alternatives }. Multi-word concept
    # phrases ("khởi động lại", "post office") are matched greedily first.
    param([string]$Query)
    Initialize-MenuSearchConcepts
    $raw = @((ConvertTo-MenuSearchText $Query) -split ' ' | Where-Object { $_ })
    # A lone "vs" means Visual Studio ("order vs"); "vs code" — or "vs c..."
    # while it's still being typed — stays VS Code.
    $tokens = @(for ($k = 0; $k -lt $raw.Count; $k++) {
        $next = if ($k + 1 -lt $raw.Count) { $raw[$k + 1] } else { "" }
        if ($raw[$k] -eq "vs" -and -not ($next -and "code".StartsWith($next))) { "visual"; "studio" } else { $raw[$k] }
    })
    $terms = @()
    $i = 0
    while ($i -lt $tokens.Count) {
        $taken = 0
        for ($n = [Math]::Min($script:MaxPhraseWords, $tokens.Count - $i); $n -ge 1; $n--) {
            $phrase = $tokens[$i..($i + $n - 1)] -join ' '
            if ($script:Alternatives.ContainsKey($phrase)) {
                $terms += New-MenuSearchTerm -Literal $phrase -Alternatives $script:Alternatives[$phrase]
                $taken = $n
                break
            }
        }
        if ($taken -eq 0) {
            $isLast = $i -eq $tokens.Count - 1
            if ($isLast -or $script:StopWords -notcontains $tokens[$i]) { $terms += New-MenuSearchTerm -Literal $tokens[$i] -Alternatives @() }
            $taken = 1
        }
        $i += $taken
    }
    return $terms
}

function New-MenuSearchTerm {
    # One query term, with its synonyms pre-shaped for cheap matching:
    # single-word synonyms (plus their inflections when 4+ letters — "check"
    # finds "checks"/"checked" but not "checkout") in a HashSet, so a field
    # is tested with one Overlaps() call; multi-word synonyms in a list.
    param([string]$Literal, $Alternatives)
    $words = [Collections.Generic.HashSet[string]]::new()
    $phrases = [Collections.Generic.List[string]]::new()
    foreach ($alt in $Alternatives) {
        if ($alt -eq $Literal) { continue }
        if ($alt.Contains(' ')) { $phrases.Add(" $alt ") ; continue }
        [void]$words.Add($alt)
        if ($alt.Length -ge 4) { foreach ($suffix in $script:Inflections) { [void]$words.Add($alt + $suffix) } }
    }
    @{ Literal = $Literal; IsPhrase = $Literal.Contains(' '); SynonymWords = $words; SynonymPhrases = $phrases }
}

# Normalized fields per entry, kept across keystrokes — the entries don't
# change while a menu is open, and re-normalizing them on every key was most
# of the per-keystroke cost.
$script:FieldCache = @{}

function Get-MenuEntryFields {
    param([string]$GroupName, $Entry)
    $key = "$GroupName`0$($Entry.Path)`0$($Entry.DisplayName)`0$($Entry.Desc)"
    $fields = $script:FieldCache[$key]
    if ($null -eq $fields) {
        # Weight = how strongly a hit in that field says "this is the one"
        $fields = foreach ($f in @(@($Entry.DisplayName, 3), @($GroupName, 2), @($Entry.Desc, 1), @(($Entry.Path -replace '\.ps1$', ''), 1))) {
            $text = ConvertTo-MenuSearchText $f[0]
            $tokens = $text.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
            @{ Tokens = $tokens; Set = [Collections.Generic.HashSet[string]]::new([string[]]$tokens); Padded = " $text "; Weight = $f[1] }
        }
        $script:FieldCache[$key] = $fields
    }
    return $fields
}

function Find-MenuEntries {
    <#
    Ranks the entries of Show-GroupedMenu-style $Groups ({ Name; Entries =
    { DisplayName; Path; Desc } }) against $Query. Returns
    { Group; Entry; Score; Partial } best-first. Entries must match every
    query term; if none does, the ones matching the most terms are returned
    with Partial = $true ("closest results"). An empty query returns every
    entry in menu order.

    Matching: a typed word also matches as a prefix (results narrow while
    typing, and "databases" finds "database"); a synonym only matches whole
    words or their inflections, at 0.7x the field's weight. The loop is
    inlined (no helper calls) because it runs entries x fields x terms times
    per keystroke and PowerShell function calls are expensive.
    #>
    param(
        [Parameter(Mandatory)]$Groups,
        [string]$Query
    )

    $terms = @(Get-MenuSearchTerms -Query $Query)
    $scored = [Collections.Generic.List[object]]::new()
    $order = 0
    foreach ($group in $Groups) {
        foreach ($entry in $group.Entries) {
            $order++
            if ($terms.Count -eq 0) {
                $scored.Add([PSCustomObject]@{ Group = $group.Name; Entry = $entry; Score = 0; Matched = 0; Order = $order })
                continue
            }
            $fields = Get-MenuEntryFields -GroupName $group.Name -Entry $entry
            $score = 0.0
            $matched = 0
            foreach ($term in $terms) {
                $best = 0.0
                $literal = $term.Literal
                foreach ($field in $fields) {
                    if ($field.Weight -le $best) { continue }
                    # the typed word/phrase itself
                    $hit = $false
                    if ($term.IsPhrase) {
                        $hit = $field.Padded.Contains(" $literal")
                    } else {
                        foreach ($t in $field.Tokens) {
                            if ($t.StartsWith($literal) -or ($t.Length -ge 4 -and $literal.StartsWith($t))) { $hit = $true; break }
                        }
                    }
                    if ($hit) { $best = $field.Weight; continue }
                    # a synonym
                    $hit = $field.Set.Overlaps($term.SynonymWords)
                    if (-not $hit) { foreach ($p in $term.SynonymPhrases) { if ($field.Padded.Contains($p)) { $hit = $true; break } } }
                    if ($hit) { $best = [Math]::Max($best, $field.Weight * 0.7) }
                }
                if ($best -gt 0) { $matched++; $score += $best }
            }
            $scored.Add([PSCustomObject]@{ Group = $group.Name; Entry = $entry; Score = $score; Matched = $matched; Order = $order })
        }
    }

    if ($terms.Count -eq 0) { return $scored | ForEach-Object { [PSCustomObject]@{ Group = $_.Group; Entry = $_.Entry; Score = 0; Partial = $false } } }

    $maxMatched = 0
    foreach ($s in $scored) { if ($s.Matched -gt $maxMatched) { $maxMatched = $s.Matched } }
    if ($maxMatched -eq 0) { return @() }
    $partial = $maxMatched -lt $terms.Count
    $scored | Where-Object { $_.Matched -eq $maxMatched } |
        Sort-Object @{ Expression = "Score"; Descending = $true }, Order |
        ForEach-Object { [PSCustomObject]@{ Group = $_.Group; Entry = $_.Entry; Score = $_.Score; Partial = $partial } }
}
Export-ModuleMember -Function ConvertTo-MenuSearchText, Get-MenuSearchTerms, Find-MenuEntries
