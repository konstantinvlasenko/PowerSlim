from nose.tools import ok_, eq_

import clr
clr.AddReference( "System.Management.Automation" )
from System.Management.Automation import PowerShell

def setup():

  global p
  p = PowerShell.Create()

  s = open( "slim.ps1" ).read()
  i_( s )

script = lambda s: p.AddScript(s)

def i_(s):

  script(s)
  global res
  res = (p.Invoke())
 
def test_powershell():
  
  i_( "$a=12;$a" )
  eq_(res[0], 12)

def test_one_row_table():
  
  i_( "$a = 1, 2, 3" )
  i_( "Test-OneRowTable( $a )" )

  eq_(res[0], True)
  
  i_( "$a = (1,2,3), 2, 3" )
  i_( "Test-OneRowTable( $a )" )
  
  eq_(res[0], False)

def test_is_chunk():

  i_( "$a='not chunk'" )
  i_( "ischunk($a)" )

  eq_(res[0], False)

  i_( "$a='[chunk]'" )
  i_( "ischunk($a)" )

  eq_(res[0], True)
