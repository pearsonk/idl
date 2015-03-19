param (
  [int]$timeout = 3600000
)

function Get-FileHash($targetFile) {
  $size = (Get-Item $targetFile).length / 1000000
  Write-Host "Hashing $size MB $targetFile"
  $readStream = [system.io.file]::openread($targetFile)
  $hasher = [System.Security.Cryptography.HashAlgorithm]::create('sha256')
  $hash = $hasher.ComputeHash($readStream)
  $readStream.Close()
  return [system.bitconverter]::toString($hash)
}


Function PerformDownload ($url, $targetFile, $expectedHash) {
    if (($expectedHash) -and (Test-Path $targetFile)) {
      $hash = Get-FileHash($targetFile)
      if ($hash -eq $expectedHash) {
         Write-Host "[Already have $targetFile with hash $hash so skipping download]"
         return
      } else {
         Write-Host "[Already have $targetFile but its hash $hash is not $expectedHash so downloading again]"
      }
    } 
    Write-Host "Input URL: [$url] downloading to [$targetFile]"

    # Create the request and do our best to avoid any local caching or socket reusing (causes backend caching)
    # Core of this code is by Jason Niver's blog.
    # http://blogs.msdn.com/b/jasonn/archive/2008/06/13/downloading-files-from-the-internet-in-powershell-with-progress.aspx
    $uri = New-Object "System.Uri" "$url" 
    $request = [System.Net.HttpWebRequest]::Create($uri) 
    $request.CachePolicy = New-Object System.Net.Cache.HttpRequestCachePolicy([System.Net.Cache.HttpRequestCacheLevel]::NoCacheNoStore)
    $request.Headers.Add("Cache-Control", "no-cache")
    $request.KeepAlive = 0
    $request.set_Timeout($timeout) 
    $tmp1 = $request.RequestUri
    $tmp2 = $request.Timeout

    # Make the actual request 
    try {
      $response = $request.GetResponse()
      # Get the file size, allowing the pretty progress bar 
      $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024) 
      Write-Host "Total length is $totalLength KiB."
    
      # Set up the buffer for reading the file and writing it to disk
      $responseStream = $response.GetResponseStream() 
      $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create 
      $buffer = new-object byte[] 10KB 
      $count = $responseStream.Read($buffer,0,$buffer.length) 
      $downloadedBytes = $count 

      # Download the file and write to disk
      while ($count -gt 0) 
      {  
        $targetStream.Write($buffer, 0, $count) 
        $count = $responseStream.Read($buffer,0,$buffer.length) 
        $downloadedBytes = $downloadedBytes + $count 
        Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
      } 
      # Clean up after ourselves
      $targetStream.Flush()
      $targetStream.Close() 
      $targetStream.Dispose() 
      $responseStream.Dispose() 
      
      # hash file
      $hash = Get-FileHash($targetFile)
      Write-Host "$hash calculated for downloaded $url"
      if ($expectedHash -and ($hash -ne $expectedHash)) {
         Write-Host "ERROR: $url does not contain the expected content (found hash $hash rather than $expectedHash)"
         Exit 2
       } 
    } catch {
       Write-Host "Unable to download $url error " $_.Exception.Message
       Exit 1
    }
}
