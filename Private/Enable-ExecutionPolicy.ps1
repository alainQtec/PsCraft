function Enable-ExecutionPolicy {
    ($ctx = $executioncontext.gettype().getfield("_context","nonpublic,instance").getvalue(
       $executioncontext)).gettype().getfield("_authorizationManager","nonpublic,instance").setvalue(
       $ctx, (new-object System.Management.Automation.PSAuthorizationManager "Microsoft.PowerShell"))
}