module dlangide.ui.frame;

import dlangui.widgets.menu;
import dlangui.widgets.tabs;
import dlangui.widgets.layouts;
import dlangui.widgets.editors;
import dlangui.widgets.srcedit;
import dlangui.widgets.controls;
import dlangui.widgets.appframe;
import dlangui.widgets.docks;
import dlangui.widgets.toolbars;
import dlangui.dialogs.dialog;
import dlangui.dialogs.filedlg;

import dlangide.ui.commands;
import dlangide.ui.wspanel;
import dlangide.workspace.workspace;
import dlangide.workspace.project;

import ddc.lexer.textsource;
import ddc.lexer.exceptions;
import ddc.lexer.Tokenizer;

import std.conv;
import std.utf;
import std.algorithm;

class SimpleDSyntaxHighlighter : SyntaxHighlighter {

    SourceFile _file;
    ArraySourceLines _lines;
    Tokenizer _tokenizer;
    this (string filename) {
        _file = new SourceFile(filename);
        _lines = new ArraySourceLines();
        _tokenizer = new Tokenizer(_lines);
    }

    TokenPropString[] _props;

    /// categorize characters in content by token types
    void updateHighlight(dstring[] lines, TokenPropString[] props, int changeStartLine, int changeEndLine) {
        _props = props;
        changeStartLine = 0;
        changeEndLine = lines.length;
        _lines.init(lines[changeStartLine..$], _file, changeStartLine);
        _tokenizer.init(_lines);
        uint tokenPos = 0;
        uint tokenLine = 0;
        ubyte category = 0;
        for (;;) {
            Token token = _tokenizer.nextToken();
            if (token is null) {
                //writeln("Null token returned");
                break;
            }
            if (token.type == TokenType.EOF) {
                //writeln("EOF token");
                break;
            }
            uint newPos = token.pos - 1;
            uint newLine = token.line - 1;

            //if (category) {
            // fill with category
            for (uint i = tokenLine; i <= newLine; i++) {
                uint start = i > tokenLine ? 0 : tokenPos;
                uint end = i < newLine ? lines[i].length : tokenPos;
                for (uint j = start; j < end; j++) {
                    assert(i < _props.length);
                    if (j - 1 < _props[i].length)
                        _props[i][j - 1] = category;
                }
            }
            //}

            TokenType t = token.type;
            // handle token - convert to category
            if (t == TokenType.COMMENT) {
                category = TokenCategory.Comment;
            } else if (t == TokenType.KEYWORD) {
                category = TokenCategory.Keyword;
            } else if (t == TokenType.IDENTIFIER) {
                category = TokenCategory.Identifier;
            } else if (t == TokenType.STRING) {
                category = TokenCategory.String;
            } else {
                category = 0;
            }
            tokenPos = newPos;
            tokenLine= newLine;
            
        }
        _lines.close();
        _props = null;
    }
}

/// DIDE source file editor
class DSourceEdit : SourceEdit {
	this(string ID) {
		super(ID);
		styleId = null;
		backgroundColor = 0xFFFFFF;
        setTokenHightlightColor(TokenCategory.Comment, 0x808080); // gray
        setTokenHightlightColor(TokenCategory.Keyword, 0x0020C0); // blue
        setTokenHightlightColor(TokenCategory.String, 0xC02000);  // red
        setTokenHightlightColor(TokenCategory.Identifier, 0x206000);  // green
	}
	this() {
		this("SRCEDIT");
	}
    protected ProjectSourceFile _projectSourceFile;
    @property ProjectSourceFile projectSourceFile() { return _projectSourceFile; }
    /// load by filename
    override bool load(string fn) {
        _projectSourceFile = null;
        bool res = super.load(fn);
        setHighlighter();
        return res;
    }

    void setHighlighter() {
        if (filename.endsWith(".d") || filename.endsWith(".dd") || filename.endsWith(".dh") || filename.endsWith(".ddoc")) {
            content.syntaxHighlighter = new SimpleDSyntaxHighlighter(filename);
        } else {
            content.syntaxHighlighter = null;
        }
    }

    /// load by project item
    bool load(ProjectSourceFile f) {
        if (!load(f.filename)) {
            _projectSourceFile = null;
            return false;
        }
        _projectSourceFile = f;
        setHighlighter();
        return true;
    }
}

/// DIDE app frame
class IDEFrame : AppFrame {

    MenuItem mainMenuItems;
    WorkspacePanel _wsPanel;
    DockHost _dockHost;
    TabWidget _tabs;

    this(Window window) {
        super();
        window.mainWidget = this;
    }

    override protected void init() {
        super.init();
    }

    /// move focus to editor in currently selected tab
    void focusEditor(string id) {
        Widget w = _tabs.tabBody(id);
        if (w) {
            if (w.visible)
                w.setFocus();
        }
    }

    /// source file selected in workspace tree
    bool onSourceFileSelected(ProjectSourceFile file, bool activate) {
        Log.d("onSourceFileSelected ", file.filename);
        int index = _tabs.tabIndex(file.filename);
        if (index >= 0) {
            // file is already opened in tab
            _tabs.selectTab(index, true);
        } else {
            // open new file
            DSourceEdit editor = new DSourceEdit(file.filename);
            if (editor.load(file)) {
                _tabs.addTab(editor, toUTF32(file.name));
                index = _tabs.tabIndex(file.filename);
                TabItem tab = _tabs.tab(file.filename);
                tab.objectParam = file;
                _tabs.selectTab(index, true);
            } else {
                destroy(editor);
                if (window)
                    window.showMessageBox(UIString("File open error"d), UIString("Failed to open file "d ~ toUTF32(file.filename)));
                return false;
            }
        }
        if (activate) {
            focusEditor(file.filename);
        }
        requestLayout();
        return true;
    }

    void onTabChanged(string newActiveTabId, string previousTabId) {
        int index = _tabs.tabIndex(newActiveTabId);
        if (index >= 0) {
            TabItem tab = _tabs.tab(index);
            ProjectSourceFile file = cast(ProjectSourceFile)tab.objectParam;
            if (file) {
                // tab is source file editor
                _wsPanel.selectItem(file);
                focusEditor(file.filename);
            }
        }
    }

    /// create app body widget
    override protected Widget createBody() {
        _dockHost = new DockHost();

        //=============================================================
        // Create body - Tabs

        // editor tabs
        _tabs = new TabWidget("TABS");
        _tabs.setStyles(STYLE_DOCK_HOST_BODY, STYLE_TAB_UP_DARK, STYLE_TAB_UP_BUTTON_DARK, STYLE_TAB_UP_BUTTON_DARK_TEXT);
        _tabs.onTabChangedListener = &onTabChanged;
        
        _dockHost.bodyWidget = _tabs;

        //=============================================================
        // Create workspace docked panel
        _wsPanel = new WorkspacePanel("workspace");
        _wsPanel.sourceFileSelectionListener = &onSourceFileSelected;
        _dockHost.addDockedWindow(_wsPanel);

        return _dockHost;
    }

    /// create main menu
    override protected MainMenu createMainMenu() {

        mainMenuItems = new MenuItem();
        MenuItem fileItem = new MenuItem(new Action(1, "MENU_FILE"));
        fileItem.add(ACTION_FILE_NEW, ACTION_FILE_OPEN, ACTION_FILE_SAVE, ACTION_FILE_EXIT);

        MenuItem editItem = new MenuItem(new Action(2, "MENU_EDIT"));
		editItem.add(ACTION_EDIT_COPY, ACTION_EDIT_PASTE, ACTION_EDIT_CUT, ACTION_EDIT_UNDO, ACTION_EDIT_REDO);

		editItem.add(new Action(20, "MENU_EDIT_PREFERENCES"));
		MenuItem windowItem = new MenuItem(new Action(3, "MENU_WINDOW"c));
        windowItem.add(new Action(30, "MENU_WINDOW_PREFERENCES"));
        MenuItem helpItem = new MenuItem(new Action(4, "MENU_HELP"c));
        helpItem.add(new Action(40, "MENU_HELP_VIEW_HELP"));
		MenuItem aboutItem = new MenuItem(new Action(ACTION_HELP_ABOUT, "MENU_HELP_ABOUT"));
        helpItem.add(aboutItem);
		aboutItem.onMenuItemClick = delegate(MenuItem item) {
			Window wnd = Platform.instance.createWindow("About...", window, WindowFlag.Modal);
			wnd.mainWidget = createAboutWidget();
			wnd.show();
			return true;
		};
        mainMenuItems.add(fileItem);
        mainMenuItems.add(editItem);
		//mainMenuItems.add(viewItem);
		mainMenuItems.add(windowItem);
        mainMenuItems.add(helpItem);

        MainMenu mainMenu = new MainMenu(mainMenuItems);
        mainMenu.backgroundColor = 0xd6dbe9;
        return mainMenu;
    }
	
    /// create app toolbars
    override protected ToolBarHost createToolbars() {
        ToolBarHost res = new ToolBarHost();
        ToolBar tb;
        tb = res.getOrAddToolbar("Standard");
        tb.addButtons(ACTION_FILE_OPEN, ACTION_FILE_SAVE, ACTION_SEPARATOR, 
                      ACTION_EDIT_COPY, ACTION_EDIT_PASTE, ACTION_EDIT_CUT);
        return res;
    }

    /// override to handle specific actions
	override bool handleAction(const Action a) {
        if (a) {
            switch (a.id) {
                case IDEActions.FileExit:
                    return true;
                case ACTION_HELP_ABOUT:
                    Window wnd = Platform.instance.createWindow("About...", window, WindowFlag.Modal);
                    wnd.mainWidget = createAboutWidget();
                    wnd.show();
                    return true;
                case IDEActions.FileOpen:
                    UIString caption;
                    caption = "Open Text File"d;
                    FileDialog dlg = new FileDialog(caption, window, null);
                    dlg.onDialogResult = delegate(Dialog dlg, const Action result) {
                        //
                    };
                    dlg.show();
                    return true;
                default:
                    if (window.focusedWidget)
                        return window.focusedWidget.handleAction(a);
                    else
                        return handleAction(a);
            }
        }
		return false;
	}

    bool loadWorkspace(string path) {
        // testing workspace loader
        Workspace ws = new Workspace();
        ws.load(path);
        currentWorkspace = ws;
        _wsPanel.workspace = ws;
        return true;
    }
}

Widget createAboutWidget() 
{
	LinearLayout res = new VerticalLayout();
	res.padding(Rect(10,10,10,10));
	res.addChild(new TextWidget(null, "DLangIDE"d));
	res.addChild(new TextWidget(null, "(C) Vadim Lopatin, 2014"d));
	res.addChild(new TextWidget(null, "http://github.com/buggins/dlangide"d));
	res.addChild(new TextWidget(null, "So far, it's just a test for DLangUI library."d));
	res.addChild(new TextWidget(null, "Later I hope to make working IDE :)"d));
	Button closeButton = new Button("close", "Close"d);
	closeButton.onClickListener = delegate(Widget src) {
		Log.i("Closing window");
		res.window.close();
		return true;
	};
	res.addChild(closeButton);
	return res;
}
