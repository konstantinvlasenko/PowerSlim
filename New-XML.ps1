#
# http://poshcode.org/1244
#
$xlr8r = [type]::gettype("System.Management.Automation.TypeAccelerators")
$xlinq = [Reflection.Assembly]::Load("System.Xml.Linq, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")
$xlinq.GetTypes() | ? { $_.IsPublic -and !$_.IsSerializable -and $_.Name -ne "Extensions" -and !$xlr8r::Get[$_.Name] } | % {
  $xlr8r::Add( $_.Name, $_.FullName )
}

function New-Xml {
Param(
   [Parameter(Mandatory = $true, Position = 0)]
   [System.Xml.Linq.XName]$root
,
   [Parameter(Mandatory = $false)]
   [string]$Version = "1.0"
,
   [Parameter(Mandatory = $false)]
   [string]$Encoding = "UTF-8"
,
   [Parameter(Mandatory = $false)]
   [string]$Standalone = "yes"
,
   [Parameter(Position=99, Mandatory = $false, ValueFromRemainingArguments=$true)]
   [PSObject[]]$args
)
BEGIN {
   if(![string]::IsNullOrEmpty( $root.NamespaceName )) {
      Function New-XmlDefaultElement {
         Param([System.Xml.Linq.XName]$tag)
         if([string]::IsNullOrEmpty( $tag.NamespaceName )) {
            $tag = $($root.Namespace) + $tag
         }
         New-XmlElement $tag @args
      }
      Set-Alias xe New-XmlDefaultElement
   }
}
PROCESS {
   #New-Object XDocument (New-Object XDeclaration "1.0", "UTF-8", "yes"),(
   New-Object XDocument (New-Object XDeclaration $Version, $Encoding, $standalone),(
      New-Object XElement $(
         $root
         #  foreach($ns in $namespace){
            #  $name,$url = $ns -split ":",2
            #  New-Object XAttribute ([XNamespace]::Xmlns + $name),$url
         #  }
         while($args) {
            $attrib, $value, $args = $args
            if($attrib -is [ScriptBlock]) {
               &$attrib
            } elseif ( $value -is [ScriptBlock] -and "-Content".StartsWith($attrib)) {
               &$value
            } elseif ( $value -is [XNamespace]) {
               New-XmlAttribute ([XNamespace]::Xmlns + $attrib.TrimStart("-")) $value
            } else {
               New-XmlAttribute $attrib.TrimStart("-") $value
            }
         }
      ))
}
END {
   Set-Alias xe New-XmlElement
}
}
function New-XmlAttribute {
Param($name,$value)
   New-Object XAttribute $name,$value
}
Set-Alias xa New-XmlAttribute


function New-XmlElement {
  Param([System.Xml.Linq.XName]$tag)
  Write-Verbose $($args | %{ $_ | Out-String } | Out-String)
  New-Object XElement $(
     $tag
     while($args) {
        $attrib, $value, $args = $args
        if($attrib -is [ScriptBlock]) {
           &$attrib
        } elseif ( $value -is [ScriptBlock] -and "-Content".StartsWith($attrib)) {
           &$value
        } elseif ( $value -is [XNamespace]) {
            New-Object XAttribute ([XNamespace]::Xmlns + $attrib.TrimStart("-")),$value
        } else {
           New-Object XAttribute $attrib.TrimStart("-"), $value
        }
     }
   )
}
Set-Alias xe New-XmlElement




####################################################################################################
###### EXAMPLE SCRIPT: NOTE the `: in the http`: is only there for PoshCode, you can just use http:
# [XNamespace]$dc = "http`://purl.org/dc/elements/1.1"
#
# $xml = New-Xml rss -dc $dc -version "2.0" {
#    xe channel {
#       xe title {"Test RSS Feed"}
#       xe link {"http`://HuddledMasses.org"}
#       xe description {"An RSS Feed generated simply to demonstrate my XML DSL"}
#       xe ($dc + "language") {"en"}
#       xe ($dc + "creator") {"Jaykul@HuddledMasses.org"}
#       xe ($dc + "rights") {"Copyright 2009, CC-BY"}
#       xe ($dc + "date") {(Get-Date -f u) -replace " ","T"}
#       xe item {
#          xe title {"The First Item"}
#          xe link {"http`://huddledmasses.org/new-site-new-layout-lost-posts/"}
#          xe guid -isPermaLink true {"http`://huddledmasses.org/new-site-new-layout-lost-posts/"}
#          xe description {"Ema Lazarus' Poem"}
#          xe pubDate  {(Get-Date 10/31/2003 -f u) -replace " ","T"}
#       }
#    }
# }
#
# $xml.Declaration.ToString()  ## I can't find a way to have this included in the $xml.ToString()
# $xml.ToString()
#
####### OUTPUT: (NOTE: I added the space in the http: to paste it on PoshCode -- those aren't in the output)
# <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
# <rss xmlns:dc="http ://purl.org/dc/elements/1.1" version="2.0">
#   <channel>
#     <title>Test RSS Feed</title>
#     <link>http ://HuddledMasses.org</link>
#     <description>An RSS Feed generated simply to demonstrate my XML DSL</description>
#     <dc:language>en</dc:language>
#     <dc:creator>Jaykul@HuddledMasses.org</dc:creator>
#     <dc:rights>Copyright 2009, CC-BY</dc:rights>
#     <dc:date>2009-07-26T00:50:08Z</dc:date>
#     <item>
#       <title>The First Item</title>
#       <link>http ://huddledmasses.org/new-site-new-layout-lost-posts/</link>
#       <guid isPermaLink="true">http ://huddledmasses.org/new-site-new-layout-lost-posts/</guid>
#       <description>Ema Lazarus' Poem</description>
#       <pubDate>2003-10-31T00:00:00Z</pubDate>
#     </item>
#   </channel>
# </rss>


####################################################################################################
###### ANOTHER EXAMPLE SCRIPT, this time with a default namespace
## IMPORTANT! ## NOTE that I use the "xe" shortcut which is redefined when you specify a namespace
##            ## for the root element, so that all child elements (by default) inherit that.
##            ## You can still control the prefixes by passing the namespace as a parameter
##            ## e.g.: -atom $atom
###### The `: in the http`: is still only there for PoshCode, you can just use http: ...
####################################################################################################
#
#   [XNamespace]$atom="http`://www.w3.org/2005/Atom"
#   [XNamespace]$dc = "http`://purl.org/dc/elements/1.1"
#  
#   New-Xml ($atom + "feed") -Encoding "UTF-16" -$([XNamespace]::Xml +'lang') "en-US" -dc $dc {
#      xe title {"Test First Entry"}
#      xe link {"http`://HuddledMasses.org"}
#      xe updated {(Get-Date -f u) -replace " ","T"}
#      xe author {
#         xe name {"Joel Bennett"}
#         xe uri {"http`://HuddledMasses.org"}
#      }
#      xe id {"http`://huddledmasses.org/" }
#
#      xe entry {
#         xe title {"Test First Entry"}
#         xe link {"http`://HuddledMasses.org/new-site-new-layout-lost-posts/" }
#         xe id {"http`://huddledmasses.org/new-site-new-layout-lost-posts/" }
#         xe updated {(Get-Date 10/31/2003 -f u) -replace " ","T"}
#         xe summary {"Ema Lazarus' Poem"}
#         xe link -rel license -href "http://creativecommons.org/licenses/by/3.0/" -title "CC By-Attribution"
#         xe ($dc + "rights") {"Copyright 2009, Some rights reserved (licensed under the Creative Commons Attribution 3.0 Unported license)"}
#         xe category -scheme "http://huddledmasses.org/tag/" -term "huddled-masses"
#      }
#   } | % { $_.Declaration.ToString(); $_.ToString() }
#
####### OUTPUT: (NOTE: I added the spaces again to the http: to paste it on PoshCode)
# <?xml version="1.0" encoding="UTF-16" standalone="yes"?>
# <feed xml:lang="en-US" xmlns="http ://www.w3.org/2005/Atom">
#   <title>Test First Entry</title>
#   <link>http ://HuddledMasses.org</link>
#   <updated>2009-07-29T17:25:49Z</updated>
#   <author>
#      <name>Joel Bennett</name>
#      <uri>http ://HuddledMasses.org</uri>
#   </author>
#   <id>http ://huddledmasses.org/</id>
#   <entry>
#     <title>Test First Entry</title>
#     <link>http ://HuddledMasses.org/new-site-new-layout-lost-posts/</link>
#     <id>http ://huddledmasses.org/new-site-new-layout-lost-posts/</id>
#     <updated>2003-10-31T00:00:00Z</updated>
#     <summary>Ema Lazarus' Poem</summary>
#     <link rel="license" href="http ://creativecommons.org/licenses/by/3.0/" title="CC By-Attribution" />
#     <dc:rights>Copyright 2009, Some rights reserved (licensed under the Creative Commons Attribution 3.0 Unported license)</dc:rights>
#     <category scheme="http ://huddledmasses.org/tag/" term="huddled-masses" />
#   </entry>
# </feed>
# 
#