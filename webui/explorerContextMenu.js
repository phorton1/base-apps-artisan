<!DOCTYPE html>
<html>
<head>
	<meta http-equiv="content-type" content="text/html; charset=ISO-8859-1">
	<title>Fancytree - Example: Context Menu</title>

	<script src="//code.jquery.com/jquery-1.11.3.min.js" type="text/javascript"></script>
	<script src="//code.jquery.com/ui/1.11.4/jquery-ui.min.js" type="text/javascript"></script>

	<link href="../src/skin-win7/ui.fancytree.css" rel="stylesheet" type="text/css">
	<script src="../src/jquery.fancytree.js" type="text/javascript"></script>
	<script src="../src/jquery.fancytree.dnd.js" type="text/javascript"></script>

	<!-- jquery.contextmenu,  A Beautiful Site (http://abeautifulsite.net/) -->
	<script src="../lib/contextmenu-abs/jquery.contextMenu-custom.js" type="text/javascript"></script>
	<link href="../lib/contextmenu-abs/jquery.contextMenu.css" rel="stylesheet" type="text/css" >

	<!-- Start_Exclude: This block is not part of the sample code -->
	<link href="../lib/prettify.css" rel="stylesheet">
	<script src="../lib/prettify.js" type="text/javascript"></script>
	<link href="sample.css" rel="stylesheet" type="text/css">
	<script src="sample.js" type="text/javascript"></script>
	<!-- End_Exclude -->

	<script type="text/javascript">

	// --- Implement Cut/Copy/Paste --------------------------------------------
	var clipboardNode = null;
	var pasteMode = null;

	function copyPaste(action, node) {
		switch( action ) {
		case "cut":
		case "copy":
			clipboardNode = node;
			pasteMode = action;
			break;
		case "paste":
			if( !clipboardNode ) {
				alert("Clipoard is empty.");
				break;
			}
			if( pasteMode == "cut" ) {
				// Cut mode: check for recursion and remove source
				var cb = clipboardNode.toDict(true);
				if( node.isDescendantOf(cb) ) {
					alert("Cannot move a node to it's sub node.");
					return;
				}
				node.addChildren(cb);
				node.render();
				clipboardNode.remove();
			} else {
				// Copy mode: prevent duplicate keys:
				var cb = clipboardNode.toDict(true, function(dict){
					dict.title = "Copy of " + dict.title;
					delete dict.key; // Remove key, so a new one will be created
				});
				alert("cb = " + JSON.stringify(cb));
//				node.addChildren(cb);
//                node.render();
				node.applyPatch(cb);
			}
			clipboardNode = pasteMode = null;
			break;
		default:
			alert("Unhandled clipboard action '" + action + "'");
		}
	};

	// --- Contextmenu helper --------------------------------------------------
	function bindContextMenu(span) {
		// Add context menu to this node:
		$(span).contextMenu({menu: "myMenu"}, function(action, el, pos) {
			// The event was bound to the <span> tag, but the node object
			// is stored in the parent <li> tag
			var node = $.ui.fancytree.getNode(el);
			switch( action ) {
			case "cut":
			case "copy":
			case "paste":
				copyPaste(action, node);
				break;
			default:
				alert("Todo: appply action '" + action + "' to node " + node);
			}
		});
	};

	// --- Init fancytree during startup ----------------------------------------

	$(function(){
		$("#tree").fancytree({
			extensions: ["dnd"],
			activate: function(event, data) {
				var node = data.node;
				$("#echoActivated").text(node.title + ", key=" + node.key);
			},
			click: function(event, data) {
				// Close menu on click
				if( $(".contextMenu:visible").length > 0 ){
					$(".contextMenu").hide();
//					return false;
				}
			},
			keydown: function(event, data) {
				var node = data.node;
				// Eat keyboard events, when a menu is open
				if( $(".contextMenu:visible").length > 0 )
					return false;

				switch( event.which ) {

				// Open context menu on [Space] key (simulate right click)
				case 32: // [Space]
					$(node.span).trigger("mousedown", {
						preventDefault: true,
						button: 2
						})
					.trigger("mouseup", {
						preventDefault: true,
						pageX: node.span.offsetLeft,
						pageY: node.span.offsetTop,
						button: 2
						});
					return false;

				// Handle Ctrl-C, -X and -V
				case 67:
					if( event.ctrlKey ) { // Ctrl-C
						copyPaste("copy", node);
						return false;
					}
					break;
				case 86:
					if( event.ctrlKey ) { // Ctrl-V
						copyPaste("paste", node);
						return false;
					}
					break;
				case 88:
					if( event.ctrlKey ) { // Ctrl-X
						copyPaste("cut", node);
						return false;
					}
					break;
				}
			},
			/*Bind context menu for every node when its DOM element is created.
			  We do it here, so we can also bind to lazy nodes, which do not
			  exist at load-time. (abeautifulsite.net menu control does not
			  support event delegation)*/
			createNode: function(event, data){
				bindContextMenu(data.node.span);
			},
			/*Load lazy content (to show that context menu will work for new items too)*/
			lazyLoad: function(event, data){
				data.result = {url: "sample-data2.json"};
			},
			/* D'n'd, just to show it's compatible with a context menu.
			   See http://code.google.com/p/dynatree/issues/detail?id=174 */
			dnd: {
				preventVoidMoves: true, // Prevent dropping nodes 'before self', etc.
				preventRecursiveMoves: true, // Prevent dropping nodes on own descendants
				autoExpandMS: 400,
				dragStart: function(node, data) {
					return true;
				},
				dragEnter: function(node, data) {
	//               return true;
				   if(node.parent !== data.otherNode.parent)
					   return false;
				   return ["before", "after"];
				},
				dragDrop: function(node, data) {
					data.otherNode.moveTo(node, data.hitMode);
				}
			}
		});
	});
</script>
</head>

<body class="example">
	<h1>Example: Context Menu</h1>
	<div class="description">
	   Implementation of a context menu. Right-click a node and see what happens.
		<ul>
		<li>Also [space] key is supported to open the menu.
		<li>This example also demonstrates, how to copy or move branches and how
			to implement clipboard functionality.
		<li>A keyboard handler implements Cut, Copy, and Paste with <code>Ctrl-X</code>,
			<code>Ctrl-C</code>, <code>Ctrl-V</code>.
		</ul>
		This sample uses the jQuery Context Menu Plugin by Cory S.N. LaViska.
		Visit  <a href="http://abeautifulsite.net/">A Beautiful Site</a> for usage and more information.
		<br>
		<b>NOTE:</b></br>
		I had to <a href="http://code.google.com/p/dynatree/issues/detail?id=174">patch Cory's code</a> in order to make it work. Please understand, that I am not able to support this plugin. There are many other context menus
		out there :-)
	</div>
	<div>
		<label for="skinswitcher">Skin:</label> <select id="skinswitcher"></select>
	</div>

	<!-- Definition of context menu -->
	<ul id="myMenu" class="contextMenu">
		<li class="edit"><a href="#edit">Edit</a></li>
		<li class="cut separator"><a href="#cut">Cut</a></li>
		<li class="copy"><a href="#copy">Copy</a></li>
		<li class="paste"><a href="#paste">Paste</a></li>
		<li class="delete"><a href="#delete">Delete</a></li>
		<li class="quit separator"><a href="#quit">Quit</a></li>
	</ul>

	<!-- Definition tree structure -->
	<div id="tree">
		<ul>
			<li id="id1" title="Look, a tool tip!">item1 with key and tooltip
			<li id="id2" class="activate">item2: activated on init
			<li id="id3" class="folder">Folder with some children
				<ul>
					<li id="id3.1">Sub-item 3.1
					<li id="id3.2">Sub-item 3.2
				</ul>

			<li id="id4" class="expanded">Document with some children (expanded on init)
				<ul>
					<li id="id4.1">Sub-item 4.1
					<li id="id4.2">Sub-item 4.2
				</ul>

			<li id="id5" class="lazy folder">Lazy folder
		</ul>
	</div>

	<div>Selected node: <span id="echoActivated">-</span></div>

	<!-- Start_Exclude: This block is not part of the sample code -->
	<hr>
	<p class="sample-links  no_code">
		<a class="hideInsideFS" href="https://github.com/mar10/fancytree">jquery.fancytree.js project home</a>
		<a class="hideOutsideFS" href="#">Link to this page</a>
		<a class="hideInsideFS" href="index.html">Example Browser</a>
		<a href="#" id="codeExample">View source code</a>
	</p>
	<pre id="sourceCode" class="prettyprint" style="display:none"></pre>
	<!-- End_Exclude -->
</body>
</html>
