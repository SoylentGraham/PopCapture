using UnityEngine;
using System.Collections;
using System.Runtime.InteropServices;
using System;

public class TestPipes : MonoBehaviour {

	private string	mMapName = "/frame65378";
	private int 	mFileDesc = -1;
	private byte[]	mBytes = null;
	private int		mLength = 3686432;

	const int PROT_NONE = 0x0;
	const int PROT_READ = 0x4;
	const int PROT_WRITE = 0x2;
	const int MAP_SHARED = 0x0001;
	const int O_RDONLY = 0x0000;
	const int O_RDWR = 0x0002;




	//	libSystem.dylib
	[DllImport ("system", SetLastError=true)]
	private static extern IntPtr mmap(IntPtr addr, Int32 length, int prot, int flags,int fd, Int32  offset);
	
	[DllImport ("system", SetLastError=true)]
	private static extern int shm_open(IntPtr name, int oflag, int mode);

	[DllImport ("system")]
	private static extern int getpid ();

	public void Start()
	{
		//	attempt memory map
	}

	 void OpenMapFile()
	{
		bool ReadOnly = true;
		int OpenFlags = ReadOnly ? O_RDONLY : O_RDWR;
		int MapFlags = ReadOnly ? PROT_READ : PROT_READ | PROT_WRITE;
		int MapMode = MAP_SHARED;
		MAP_32BIT

		if (mFileDesc < 0) {
			IntPtr p = Marshal.StringToHGlobalAnsi (mMapName);
			//const char* pAnsi = static_cast<const char*>(p.ToPointer());

			int mode = 0200;
			//int mode = 0222;
			mFileDesc = shm_open (p, OpenFlags, mode);
		}

		if (mFileDesc < 0)
			return;

		Debug.Log ("mmap( 0, " + mLength + ", PROT_READ, MAP_SHARED, " + mFileDesc + ", 0)");
		IntPtr map = mmap ( (IntPtr)0, mLength, MapFlags, MAP_SHARED, mFileDesc, 0);
		int Win32Error = Marshal.GetLastWin32Error ();
		Debug.Log ("map result " + map);
		int MapError = (int)map;
		if (MapError == -1) {
			Debug.Log ("mmap failed: " + Win32Error );
			return;
		}
		if ( map == IntPtr.Zero )
			return;


		try
		{
			int CopyLength = 1;
			mBytes = new byte[CopyLength];
			Marshal.Copy( map, mBytes, 0, CopyLength);
		}
		catch ( Exception e )
		{
			Debug.Log ("exception: " + e.Message);
		}
	}

	 void OnGUI()
	{
	//	if (!Camera.current)
	//		return;

		//	Rect rect = Camera.current.pixelRect;
		Rect rect = new Rect (0, 0, Screen.width, Screen.height);
		rect.width -= 40;
		rect.x += 20;
		rect.height = 40;
		int pid = getpid ();
		GUI.Label (rect, "Hello " + pid );
		rect.y += rect.height + 10;
		
		GUI.Label (rect, "file desc " + mFileDesc );
		rect.y += rect.height + 10;
		
		mMapName = GUI.TextField (rect, mMapName);
		rect.y += rect.height + 10;

		if (GUI.Button (rect, "open")) {
			OpenMapFile ();
		}
		rect.y += rect.height + 10;

		if (mBytes != null) {
			string hex = BitConverter.ToString (mBytes);
			GUI.Label (rect, hex);
			rect.y += rect.height + 10;
		}
	}

}

