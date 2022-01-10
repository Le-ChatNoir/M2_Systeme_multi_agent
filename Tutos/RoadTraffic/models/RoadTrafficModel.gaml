/**
* Name: RoadTrafficModel
* Based on the internal empty template. 
* Author: Lukas
* Tags: 
*/


model RoadTrafficModel

global {
	//Get the shapes from outside GIS files
    file shape_file_buildings <- file("../includes/building.shp");
    file shape_file_roads <- file("../includes/road.shp");
    file shape_file_bounds <- file("../includes/bounds.shp");
    //Bounds of the environement
    geometry shape <- envelope(shape_file_bounds); 
    //Redefining the step time
    float step <- 10 #mn;
    int nb_people <- 100;
    //Work data
    date starting_date <- date("2019-09-01-00-00-00");
    int min_work_start <- 6;
    int max_work_start <- 8;
    int min_work_end <- 16; 
    int max_work_end <- 20; 
    float min_speed <- 1.0 #km / #h;
    float max_speed <- 5.0 #km / #h; 
    graph the_graph;
    float destroy <- 0.02;
    int repair_time <- 2;
    
    //Agentification of the GIS data
    init {
       create building from: shape_file_buildings with: [type::string(read ("NATURE"))] {
           if type="Industrial" {
               color <- #blue ;
           }
       }
       create road from: shape_file_roads ;
       //Weight the road network
       map<road,float> weights_map <- road as_map (each:: (each.destruction_coeff * each.shape.perimeter));
       //Creates the_graph from the road network
       the_graph <- as_edge_graph(road); 
       
       //Sort industrials and residential buildings
       list<building> residential_buildings <- building where (each.type="Residential");
	   list<building> industrial_buildings <- building  where (each.type="Industrial") ;
	   
	   //Creates people with different attributes
	   create people number: nb_people {
	       speed <- rnd(min_speed, max_speed);
	       start_work <- rnd (min_work_start, max_work_start);
	       end_work <- rnd(min_work_end, max_work_end);
	       living_place <- one_of(residential_buildings) ;
	       working_place <- one_of(industrial_buildings) ;
	       objective <- "resting";
	       location <- any_location_in (living_place); 
	   }
    }
    
    //Update the graph each step
    reflex update_graph{
        map<road,float> weights_map <- road as_map (each:: (each.destruction_coeff * each.shape.perimeter));
        the_graph <- the_graph with_weights weights_map;
     }
     //Repairing the road every repairtime hour (here, every 2 hours). Repairs the most damaged road
     reflex repair_road when: every(repair_time #hour) {
	     road the_road_to_repair <- road with_max_of (each.destruction_coeff) ;
	     ask the_road_to_repair {
	         destruction_coeff <- 1.0 ;
	     }
	 }
}

species building {
	//Will be either residential or industrial
    string type; 
    rgb color <- #gray  ;
    
    aspect base {
    draw shape color: color ;
    }
}

species road  {
    float destruction_coeff <- rnd(1.0,2.0) max: 2.0;
    int colorValue <- int(255*(destruction_coeff - 1)) update: int(255*(destruction_coeff - 1));
    //Color will change depending the destruction of the road
    rgb color <- rgb(min([255, colorValue]),max ([0, 255 - colorValue]),0)  
    	update: rgb(min([255, colorValue]),max ([0, 255 - colorValue]),0) ;
    
    aspect base {
    draw shape color: color ;
    }
}

//Allow people the moving skill to have access to goto
species people skills: [moving] {
    rgb color <- #yellow ;
    building living_place <- nil ;
    building working_place <- nil ;
    int start_work ;
    int end_work  ;
    string objective ; 
    //Point toward which the agent will be moving
    point the_target <- nil ;
    
    //Reflex to go to work. Change objective
    reflex time_to_work when: current_date.hour = start_work and objective = "resting" {
        objective <- "working" ;
    the_target <- any_location_in (working_place);
    }
    //Reflex to go home. Change objective
    reflex time_to_go_home when: current_date.hour = end_work and objective = "working" {
        objective <- "resting" ;
    the_target <- any_location_in (living_place); 
    } 
    //Allows the agent to move if the target isn't nil. Moves toward target using goto provided by the moving skill, following the shortest path on the_graph
    //When it arrives at destination, the_target is set to nil so he stops moving
    //When a people aget has moved over one or multiple road segments, it updates the road's destruction
    reflex move when: the_target != nil {
    	//Return_path to true allows to obtain the path followed, we can then compute it with the operator agent_from_geometry
	    path path_followed <- goto(target: the_target, on:the_graph, return_path: true);
	    list<geometry> segments <- path_followed.segments;
	    loop line over: segments {
	        float dist <- line.perimeter;
	        ask road(path_followed agent_from_geometry line) { 
	        destruction_coeff <- destruction_coeff + (destroy * dist / shape.perimeter);
	        }
	    }
	    if the_target = location {
	        the_target <- nil ;
	    }
    }
    
    aspect base {
    draw circle(10) color: color border: #black;
    }
}

//Allows to change the shapefile through the GUI
experiment road_traffic type: gui {
    parameter "Shapefile for the buildings:" var: shape_file_buildings category: "GIS" ;
    parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS" ;
    parameter "Shapefile for the bounds:" var: shape_file_bounds category: "GIS" ;
    parameter "Number of people agents" var: nb_people category: "People" ;
    parameter "Earliest hour to start work" var: min_work_start category: "People" min: 2 max: 8;
    parameter "Latest hour to start work" var: max_work_start category: "People" min: 8 max: 12;
    parameter "Earliest hour to end work" var: min_work_end category: "People" min: 12 max: 16;
    parameter "Latest hour to end work" var: max_work_end category: "People" min: 16 max: 23;
    parameter "minimal speed" var: min_speed category: "People" min: 0.1 #km/#h ;
    parameter "maximal speed" var: max_speed category: "People" max: 10 #km/#h;
    parameter "Value of destruction when a people agent takes a road" var: destroy category: "Road" ;
    parameter "Number of steps between two road repairs" var: repair_time category: "Road" ;
    
    
    
    //Display
    output {
	    display city_display type: opengl {
	        species building aspect: base ;
	        species road aspect: base ;
	        species people aspect: base ;
	    }
	    //Displays the charts of activities, and road status
	    display chart_display refresh: every(10#cycles) { 
	        chart "Road Status" type: series size: {1, 0.5} position: {0, 0} {
	        data "Mean road destruction" value: mean (road collect each.destruction_coeff) style: line color: #green ;
	        data "Max road destruction" value: road max_of each.destruction_coeff style: line color: #red ;
	        }
	        chart "People Objectif" type: pie style: exploded size: {1, 0.5} position: {0, 0.5}{
	        data "Working" value: people count (each.objective="working") color: #magenta ;
	        data "Resting" value: people count (each.objective="resting") color: #blue ;
	        }
	    }
	}
}