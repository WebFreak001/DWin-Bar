import dwinbar.widgets.clock;
import dwinbar.widgets.volume;
import dwinbar.widgets.workspace;

/*import dwinbar.widgets.volume;
import dwinbar.widgets.tray;
import dwinbar.widgets.workspace;*/

import dwinbar.bar;

void main(string[] args)
{
	BarConfiguration config;
	//config.fontPrimary = "Roboto Medium";
	//config.fontSecondary = "Roboto Light";

	PanelConfiguration panelConfig;
	panelConfig.height = 32;

	Bar bar = loadBar(config);

	//dfmt off
	bar.addPanel(Screen.First, Dock.Bottom, panelConfig)
		.add(new ClockWidget())
		.add(new VolumeWidget())
		.add(new WorkspaceWidget(bar.x, "HDMI-1"))
	;
	//dfmt on

	//bar.tray = panel1;
	bar.start();
}
