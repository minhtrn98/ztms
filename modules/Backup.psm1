# Passphrase-encrypted machine backup for setup\export.ps1 / setup\import.ps1.
# Format: "ZTMS1" | salt(16) | nonce(12) | tag(16) | AES-256-GCM ciphertext,
# key = PBKDF2-SHA256(passphrase, salt, 600k iterations). Portable across
# machines (unlike DPAPI), and GCM's tag makes a wrong passphrase or a
# tampered file fail loudly instead of decrypting to garbage.

$script:Magic = [Text.Encoding]::ASCII.GetBytes("ZTMS1")
$script:Iterations = 600000

function Get-TmsBackupKey {
    param([string]$Passphrase, [byte[]]$Salt)
    [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2(
        [Text.Encoding]::UTF8.GetBytes($Passphrase), $Salt, $script:Iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256, 32)
}

function Protect-TmsBackup {
    # Encrypts a UTF-8 string; returns the backup file bytes.
    param(
        [Parameter(Mandatory)][string]$PlainText,
        [Parameter(Mandatory)][string]$Passphrase
    )

    $rng = [System.Security.Cryptography.RandomNumberGenerator]
    $salt = $rng::GetBytes(16)
    $nonce = $rng::GetBytes(12)
    $plain = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipher = [byte[]]::new($plain.Length)
    $tag = [byte[]]::new(16)

    $aes = [System.Security.Cryptography.AesGcm]::new((Get-TmsBackupKey $Passphrase $salt), 16)
    try { $aes.Encrypt($nonce, $plain, $cipher, $tag) } finally { $aes.Dispose() }

    # Leading comma: return the byte[] as one object instead of unrolling it
    , [byte[]]($script:Magic + $salt + $nonce + $tag + $cipher)
}

function Unprotect-TmsBackup {
    # Decrypts backup file bytes back to the UTF-8 string. Throws on a wrong
    # passphrase, a corrupted file, or a file that isn't a ztms backup.
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][string]$Passphrase
    )

    $m = $script:Magic.Length
    if ($Data.Length -lt $m + 44 -or [Text.Encoding]::ASCII.GetString($Data, 0, $m) -ne "ZTMS1") {
        throw "Not a ztms backup file."
    }
    $salt = $Data[$m..($m + 15)]
    $nonce = $Data[($m + 16)..($m + 27)]
    $tag = $Data[($m + 28)..($m + 43)]
    $cipher = if ($Data.Length -gt $m + 44) { [byte[]]$Data[($m + 44)..($Data.Length - 1)] } else { [byte[]]::new(0) }
    $plain = [byte[]]::new($cipher.Length)

    $aes = [System.Security.Cryptography.AesGcm]::new((Get-TmsBackupKey $Passphrase ([byte[]]$salt)), 16)
    try { $aes.Decrypt([byte[]]$nonce, $cipher, [byte[]]$tag, $plain) }
    catch [System.Security.Cryptography.CryptographicException] { throw "Wrong passphrase, or the backup file is corrupted." }
    finally { $aes.Dispose() }

    [Text.Encoding]::UTF8.GetString($plain)
}

function Read-TmsPassphrase {
    # Hidden-input prompt; -Confirm asks twice and enforces a minimum length.
    param([string]$Prompt = "Backup passphrase", [switch]$Confirm)

    while ($true) {
        $first = Read-Host $Prompt -MaskInput
        if (-not $Confirm) { return $first }
        if ($first.Length -lt 8) { Write-Host "Use at least 8 characters." -ForegroundColor Yellow; continue }
        $second = Read-Host "Repeat passphrase" -MaskInput
        if ($first -ceq $second) { return $first }
        Write-Host "Passphrases don't match — try again." -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function Protect-TmsBackup, Unprotect-TmsBackup, Read-TmsPassphrase