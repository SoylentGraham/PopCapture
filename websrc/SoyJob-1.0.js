
//	add String.startsWith("Otherstring")
if (typeof String.prototype.startsWith != 'function') {
	// see below for better implementation!
	String.prototype.startsWith = function (str){
		return this.indexOf(str) == 0;
	};
}


function componentToHex(c) {
    var hex = c.toString(16);
    return hex.length == 1 ? "0" + hex : hex;
}

function rgbToHex(r, g, b) {
    return "#" + componentToHex(r) + componentToHex(g) + componentToHex(b);
}


function SoyJob($Command)
{
	this.mCommand = $Command ? $Command : null;
}

SoyJob.prototype.toString = function()
{
	return JSON.stringify( this );
}

