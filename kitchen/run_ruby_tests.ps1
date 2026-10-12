# Runs Ruby tests in a separate process using SketchUp's installed Ruby runtime.
# Does not launch, attach to, or change a SketchUp model.
param([string]$TestFile = 'test_engine.rb')
$ErrorActionPreference = 'Stop'
$taskRubyHome = 'C:/Program Files/SketchUp/SketchUp 2024'
$env:PATH = "$taskRubyHome;$env:PATH"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class KitchenRubyTestRunner {
  [DllImport("x64-ucrt-ruby320.dll", CallingConvention=CallingConvention.Cdecl)] static extern void ruby_sysinit(ref int argc, ref IntPtr argv);
  [DllImport("x64-ucrt-ruby320.dll", CallingConvention=CallingConvention.Cdecl)] static extern void ruby_init_stack(ref IntPtr stack);
  [DllImport("x64-ucrt-ruby320.dll", CallingConvention=CallingConvention.Cdecl)] static extern int ruby_setup();
  [DllImport("x64-ucrt-ruby320.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr ruby_options(int argc, IntPtr argv);
  [DllImport("x64-ucrt-ruby320.dll", CallingConvention=CallingConvention.Cdecl)] static extern int ruby_run_node(IntPtr node);
  public static int Run(string path, string library) {
    string[] args={"ruby", "--disable-gems", "-I"+library, "-I"+library+"/platform_specific", path};
    IntPtr argv=Marshal.AllocHGlobal((args.Length+1)*IntPtr.Size);
    for(int i=0;i<args.Length;i++) Marshal.WriteIntPtr(argv,i*IntPtr.Size,Marshal.StringToHGlobalAnsi(args[i]));
    Marshal.WriteIntPtr(argv,args.Length*IntPtr.Size,IntPtr.Zero);
    int argc=args.Length;
    IntPtr testArgv=argv;
    ruby_sysinit(ref argc,ref argv);
    IntPtr stack=IntPtr.Zero; ruby_init_stack(ref stack);
    if(ruby_setup()!=0) return 99;
    return ruby_run_node(ruby_options(args.Length,testArgv));
  }
}
'@
exit [KitchenRubyTestRunner]::Run((Join-Path $PSScriptRoot $TestFile), "$taskRubyHome/Tools/RubyStdLib")
