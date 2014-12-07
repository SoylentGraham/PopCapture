if (typeof GetDefaultPanoFilename != 'function') {
	
	GetDefaultPanoFilename = function() { return ''; }
}


WebGLChainRenderer.prototype = new THREE.WebGLRenderer();
function WebGLChainRenderer()
{
	THREE.WebGLRenderer.apply( this, arguments );
	
	this.super = {};
	this.super.render = this.render;
	
	var $w = 1024;
	var $h = 1024;
	var $options = { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, };
	this.mRenderTarget = new THREE.WebGLRenderTarget( $w, $h, $options );
	
	this.mPostMesh = CreatePostMesh( this.mRenderTarget );
	if ( this.mPostMesh )
	{
		this.mPostCamera = new THREE.OrthographicCamera( 0, 1, 1, 0, 0, 1 );
		this.mPostScene = new THREE.Scene();
		this.mPostScene.add( this.mPostMesh );
		console.log( this.mPostMesh );
	}
	
	this.render = this.chainrender;
}

var gPixelOffsetCount = false;

WebGLChainRenderer.prototype.chainrender = function($Scene,$Camera)
{
	if ( !this.mPostScene || !this.mPostCamera || !this.mRenderTarget )
	{
		this.super.render.call( this, $Scene, $Camera );
		return;
	}
	
	this.super.render.call( this, $Scene, $Camera, this.mRenderTarget, true );
	
	if ( gPixelOffsetCount === false )
	{
		gPixelOffsetCount = this.mPostMesh.material.uniforms.PixelOffsetCount.value;
	}
	this.mPostMesh.material.uniforms.PixelOffsetCount.value = gPixelOffsetCount;
	this.mPostMesh.material.uniforms.PixelOffsetCount.needsUpdate = true;
	
	//	render post-process shaders
	this.super.render.call( this, this.mPostScene, this.mPostCamera );
}

function AppendCoords($Coords,$Rad,$Step)
{
	$Step = CheckDefaultParam( $Step, 1 );
	
	for ( var $x=-$Rad;	$x<=$Rad;	$x+=$Step )
	{
		var $y = -$Rad;	//	first row
		$Coords.push( new THREE.Vector2( $x, $y ) );
		var $y = $Rad;	//	last row
		$Coords.push( new THREE.Vector2( $x, $y ) );
	}
	
	for ( var $y=-$Rad+1;	$y<=$Rad-1;	$y+=$Step )
	{
		var $x = -$Rad;	//	first col
		$Coords.push( new THREE.Vector2( $x, $y ) );
		var $x = $Rad;	//	last col
		$Coords.push( new THREE.Vector2( $x, $y ) );
	}
}

function CreatePostMesh($RenderTargetTexture)
{
	//	create triangles
	//	gr: 2x2 generates -1 to 1
	var geometry = new THREE.PlaneGeometry( 2, 2 );
	
	var $VertShaderElement = GetElement('postfillvertshader');
	var $FragShaderElement = GetElement('postfillfragshader');
	if ( !$VertShaderElement || !$FragShaderElement )
		return null;
	
	var $VertShader = $VertShaderElement.innerText;
	var $FragShader = $FragShaderElement.innerText;
	
	var $PixelStep = new THREE.Vector2( 1.0 / $RenderTargetTexture.width, 1.0 / $RenderTargetTexture.height );
	var $PixelOffsets = [ new THREE.Vector2(0,0) ];
	
	AppendCoords( $PixelOffsets, 1, 1 );
	AppendCoords( $PixelOffsets, 3, 1 );
	AppendCoords( $PixelOffsets, 6, 3 );
	AppendCoords( $PixelOffsets, 10, 3 );
	/*
	 AppendCoords( $PixelOffsets, 2, 1 );
	 AppendCoords( $PixelOffsets, 6, 3 );
	 AppendCoords( $PixelOffsets, 9, 3 );
	 AppendCoords( $PixelOffsets, 15, 5 );
	 */
	console.log($PixelOffsets);
	//alert($PixelOffsets.length);
	
	var uniforms =
	{
	DiffuseTexture: { type: "t", value: $RenderTargetTexture },
	PixelOffsetCount: { type: "i", value: $PixelOffsets.length },
	PixelOffsets: { type: "v2v", value: $PixelOffsets },
	PixelScalar: { type: "v2", value: $PixelStep },
	};
	
	var material = new THREE.ShaderMaterial( {
											uniforms: 		uniforms,
											vertexShader:	$VertShader,
											fragmentShader: $FragShader,
											});
	/*
	 var material = new THREE.MeshBasicMaterial({
	 color: 'red'
	 });
	 */	material.depthTest = false;
	material.side = THREE.DoubleSide;
	
	
	var mesh = new THREE.Mesh( geometry, material );
	return mesh;
}



function InitWebgl($Config)
{
	var $Container = $Config.mContainer;
	var fov = $Config.mFov;
	//	far Z matches furthest point on a cubemap...
	var $Far = Math.sqrt( $Config.mFaceResolution*$Config.mFaceResolution + $Config.mFaceResolution*$Config.mFaceResolution );
	
	$Config.mCamera = new THREE.PerspectiveCamera( fov, 1, 1, $Far );
	//	$Config.mCamera.target = new THREE.Vector3( 0, 0, 1 );
	//	$Config.mCamera.position.set( 0.001, 0.001, 0.001 );
	
	
	$Config.mDebugCamera = new THREE.PerspectiveCamera( 45, 1, 1, 10000 );
	var $CameraScale = 5.0;
	$Config.mDebugCamera.position.z = $CameraScale * 3.0;
	$Config.mDebugCamera.position.y = $CameraScale * 4.0;
	$Config.mDebugCamera.lookAt(new THREE.Vector3(0,0,0));
	
	//$Config.mDebugCameraControls = new THREE.OrbitControls( $Config.mDebugCamera, $Container );
	$Config.mDebugCameraControls = new THREE.OrbitControls( $Config.mDebugCamera, document.body );
	$Config.mDebugCameraControls.scale = 0.001;
	$Config.mDebugCameraControls.target = new THREE.Vector3(0,0,0);
	//				$Config.mDebugCameraControls.addEventListener( 'change', animate );
	
	$Config.mScene = new THREE.Scene();
	
	
	
	if ( $Config.mRenderMode == RENDERMODE_CSS )
	{
		$Config.mRendererLeft = new THREE.CSS3DRenderer();
		$Config.mRendererRight = new THREE.CSS3DRenderer();
	}
	else if ( $Config.mRenderMode == RENDERMODE_WEBGL )
	{
		$Config.mRendererLeft = new WebGLChainRenderer();
	}
	else if ( $Config.mRenderMode == RENDERMODE_CANVAS )
	{
		$Config.mRendererLeft = new THREE.CanvasRenderer();
	}
	
	if ( !$Config.mRendererLeft )
		return false;
	
	if ( $Config.mRendererLeft )
	{
		$Config.mRendererLeft.setClearColor( 0xFF0000, 1);
		$Container.appendChild( $Config.mRendererLeft.domElement );
	}
	
	if ( $Config.mRendererRight )
	{
		$Config.mRendererRight.setClearColor( 0x00FF00, 1);
		$Container.appendChild( $Config.mRendererRight.domElement );
	}
	
	
	if ( $Config.mRenderMode != RENDERMODE_CSS )
	{
		var WidthSegments = 60;
		var HeightSegments = 40;
		if ( IsMobile() )
		{
			WidthSegments /= 2;
			HeightSegments /= 2;
		}
		var Size = $Config.mFaceResolution/2;
		var geometry = new THREE.SphereGeometry( Size, WidthSegments, HeightSegments );
		//var geometry = new THREE.BoxGeometry( Size, Size, Size );
		var mtx = new THREE.Matrix4().makeScale( -1, 1, 1 );
		var rotMtx = new THREE.Matrix4().makeRotationY( Math.DegreesToRadians(-90) );
		mtx.multiply( rotMtx );
		geometry.applyMatrix( mtx );
		
		//	load default texture
		var Texture = THREE.ImageUtils.loadTexture( GetDefaultPanoFilename(), new THREE.UVMapping() );
		var material = new THREE.MeshBasicMaterial( {
												   map: Texture,
												   color: "white",
												   wireframe: false
												   } );
		
		
		$Config.mMesh = new THREE.Mesh( geometry, material );
		$Config.mScene.add( $Config.mMesh );
		
		//	gr: add this to render DOM features, but currently needs CSS camera
		//var $Cube = CreateSceneCube( renderer, $Config, false );
		
	}
	else
	{
		//	need to make both for switching back and forth
		var $CubeLeft = CreateSceneCube( $Config.mRendererLeft, $Config, true );
		var $CubeRight = CreateSceneCube( $Config.mRendererRight, $Config, true );
		//	var $CubeLeft = null;
		//	var $CubeRight = null;
		$Config.mRenderCubes = new Array( $CubeLeft, $CubeRight );
		$Config.mFeatureCubes = new Array( $CubeLeft, $CubeRight );
	}
	
	var $EyeScale = HasHashParam('pointcloud') ? 200.0 : 1.0;
	
	$Config.mSplitter = new THREE.StereoEffect( $Config.mRendererLeft, $Config.mRendererRight );
	$Config.mSplitter.separation = (1.0/$EyeScale) * $Config.mFaceResolution * $Config.mSeperation;
	//alert('seperation: ' + $Config.mSplitter.separation + ' cam far: ' + $Config.mCamera.far);
	onContainerResize($Config);
	window.addEventListener( 'resize', function() { onContainerResize($Config); }, false );
	Animate($Config);
	
	
	return true;
}

function onContainerResize($Config)
{
	var Container = $Config.mContainer;
	var w = Container.clientWidth;
	var h = Container.clientHeight;
 	
	$Config.mCamera.aspect = w / h;
	$Config.mCamera.updateProjectionMatrix();
	
	$Config.mDebugCamera.aspect = w / h;
	$Config.mDebugCamera.updateProjectionMatrix();
	
	if ( $Config.IsSplitEnabled() )
	{
		$Config.mSplitter.setSize( w, h );
	}
	else
	{
		if ( $Config.mRendererLeft )
		{
			$Config.mRendererLeft.setSize( w, h );
			$Config.mRendererLeft.setViewport( 0, 0, w, h );
			$Config.mRendererLeft.mViewport = new SoyRect( 0, 0, w, h );
		}
		
		if ( $Config.mRendererRight )
		{
			$Config.mRendererRight.setSize( 0, 0 );
			$Config.mRendererRight.setViewport( 0, 0, 0, 0 );
			$Config.mRendererRight.mViewport = new SoyRect( 0, 0, 0, 0 );
		}
	}
	
}


var gDepthNear = false;
var gDepthFar = false;
var gPointSize = false;
var gPositionScalar = false;
var gWorldYaw = false;
var gPointCloud = null;

function Animate($Config) {
	
	requestAnimationFrame( function(){Animate($Config);} );
	
	$Config.mDebugCameraControls.update();
	
	//	update shader constants
	var $PointCloud = gPointCloud;
	if ( $PointCloud )
	{
		var $Uniforms = $PointCloud.mAsset.material.uniforms;
		
		if ( gDepthNear === false )	gDepthNear = $Uniforms.gDepthNear.value;
		if ( gDepthFar === false )	gDepthFar = $Uniforms.gDepthFar.value;
		if ( gPointSize === false )	gPointSize = $Uniforms.gPointSize.value;
		if ( gWorldYaw === false )	gWorldYaw = $Uniforms.gWorldYaw.value;
		
		$Uniforms.gDepthNear.value = gDepthNear;
		$Uniforms.gDepthFar.value = gDepthFar;
		$Uniforms.gPointSize.value = gPointSize;
		$Uniforms.gWorldYaw.value = gWorldYaw;
		$Uniforms.gDepthNear.needsUpdate = true;
		$Uniforms.gDepthFar.needsUpdate = true;
		$Uniforms.gPointSize.needsUpdate = true;
		$Uniforms.gWorldYaw.needsUpdate = true;
	}
	
	if ( gPositionScalar === false )	gPositionScalar = $Config.mPositionScalar;
	$Config.mPositionScalar = gPositionScalar;
	
	Render($Config);
}

function Render($Config) {
	
	var timer = 0.0001 * Date.now();
	
	//	update camera
	var Quaternion = GetCameraQuaternion($Config.mCamera.quaternion);
	$Config.mCamera.quaternion.copy( Quaternion );
	var $Position = GetCameraPosition($Config.mCamera.position);
	$Config.mCamera.position.copy( $Position );
	$Config.mCamera.position.multiplyScalar( $Config.mPositionScalar );
	
	var QuatDebugElement = GetElement("QuatDebug");
	if ( QuatDebugElement )
		QuatDebugElement.innerText = $CurrentCameraControl + ": " + Quaternion.x + " " + Quaternion.y + " " + Quaternion.z + " " + Quaternion.w;
	
	var $PosDebugElement = GetElement("PosDebug");
	if ( $PosDebugElement )
		$PosDebugElement.innerText = $CurrentCameraControl + ": " + $Position.x + " " + $Position.y + " " + $Position.z;
	
	onContainerResize( $Config );
	
	if ( $Config.IsSplitEnabled() )
	{
		//	$Config.mSplitter.setSize( w, h );
		$Config.mSplitter.render( $Config.mScene, $Config.mCamera );
	}
	else
	{
		var $Camera = $Config.mEnableDebugCamera ? $Config.mDebugCamera : $Config.mCamera;

		if ( $Config.mRendererLeft )
		{
			$Config.mRendererLeft.render( $Config.mScene, $Camera );
			$Config.mRendererLeft.mLastCamera = $Config.mCamera;
		}
		
		if ( $Config.mRendererRight )
		{
			$Config.mRendererRight.setSize( 0, 0 );
			$Config.mRendererRight.setViewport( 0, 0, 0, 0 );
			$Config.mRendererRight.mLastCamera = null;
			//	$Config.mRendererLeftRight.render( $Config.mScene, $Config.mCamera );
		}
		
	}
	
	
}
