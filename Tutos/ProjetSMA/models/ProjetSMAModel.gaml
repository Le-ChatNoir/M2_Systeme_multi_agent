/**
* Name: ProjetSMAModel
* Based on the internal empty template. 
* Author: Lukas
* Tags: 
*/


model ProjetSMAModel

//Our World. Keeps tab on everything global, and initialization
global {
	int nb_ants_init <- 50;
	float ant_satisfaction_increment <- 0.1;
	float ant_max_satisfaction <- 1.0;
	float ant_threshold_of_dissatisfaction <- -0.8;
	file map_init <- image_file("../includes/projetsma_raster_map.png");

	
	//How our world will be initialized
	init{
		//Create the colony cell from the opacity of blue pixels from a source image
    	ask grid_cell {
            color <-  rgb(map_init at {grid_x,grid_y});
            write "(" + grid_x + ";" + grid_y + "): " + (color as list);
            //Blue cells are colony potential
            potential_colony <- 1 - (((color as list) at 1) / 255);
            //Green cells are food potential
            potential_goal <- 1 - (((color as list) at 2) / 255);
            //Red cells gets both potentiality at 0
            if(((color as list) at 0) > 200){
            	occupied <- true;
            	potential_colony <- 0.0;
            	potential_goal <- 0.0;
            }
        }
        
        //colony_cell and goal_cell are the radiant toward them. The TRUE cells list is where the potantial is at 1, ie, the center f the colony/goal
        list<grid_cell> true_colony <- grid_cell where (each.potential_colony>0.85);
        list<grid_cell> true_goal <- grid_cell where (each.potential_goal>0.95);
        
        create ant number: nb_ants_init {
        	my_cell <- one_of (true_colony);
        	my_cell.occupied <- true;
        	location <- my_cell.location;
        	location <- my_cell.location; 
        }
	}
}

//Our ant specie: every agent will be viewed as an ant
species ant skills: [fipa] {
    float size <- 1.0;
    rgb color <- #blue ;
    float satisfaction_increment <- ant_satisfaction_increment;
    float max_satisfaction <- ant_max_satisfaction;
    bool charged <- false ;
    bool fleeing <- false;
    string objective <- "feed";

    image_file my_icon <- image_file("../includes/projetsma_ant.png");
    
    grid_cell my_cell <- one_of (grid_cell) ;
    grid_cell prev_loc <- nil;
    
    //Satisfaction modified each step, gets an update during the chosing process. Initialized at 0.
    float satisfaction <- 0.0;
    
    //Reflex is movement behavior. We can add a "when: condition" that'll be executed at each step is the condition is true
    //basic_move: moves to a cell in the neighborhood of my_cell with max potential
    
    reflex move {
    	do goTo(choose_cell());
    }
   
    //Either take or put down the food
    reflex take_putdown {
	    if(my_cell.potential_goal > 0.98 and objective="feed"){
	    	charged <- true; 
	    	objective <- "home";
	    }
	    if(my_cell.potential_colony > 0.90 and objective="home"){
	    	charged <- false; 
	    	objective <- "feed";
	    }
    }
    
    /**
     * Sends a dissatisfaction message to the ants when their satisfaction is lowest.
     */
    reflex send_satisfaction when: (satisfaction < ant_threshold_of_dissatisfaction) {
        do start_conversation (to: list(ant), protocol: 'fipa-contract-net', performative: 'cfp', contents: [satisfaction]);
    }
    
    /*
     * Receives messages of dissatisfaction from all ants.
     * If the message concerns another ant around him and 
     * his satisfaction is lower than the receptionist ant 
     * then the receptionist ant (who is altruistic) will 
     * go to the other side.
     */
    reflex receive_satisfaction when: !empty(cfps) {
    	list l <- cfps;
    	loop name: mess over: l {
    		message msg <- mess;
    		if (msg.sender != self) {
    			float coef <- 1 - (self distance_to agent(msg.sender) / 10);
    			if (satisfaction * coef > float(string(""+one_of(msg.contents))) and objective != 'home') {
    				do flee;	
    			}
    		}	
    	}
    }
    
    /*
     * Choose the next free cell
     */
    grid_cell choose_cell {
		//Moving to return to the colony
   		grid_cell my_next_cell <- (my_cell.neighbors2) with_max_of ((objective="home" and not fleeing) ? each.potential_colony :
   																   ((objective="home" and fleeing) ? each.potential_goal :
   																   ((objective="feed" and not fleeing) ? each.potential_goal :
   																   ((objective="feed" and fleeing) ? each.potential_colony: 1.0))));

		float my_next_cell_potential <- (objective="home" and not fleeing) ? my_next_cell.potential_colony :
										((objective="home" and fleeing) ? my_next_cell.potential_goal :
										((objective="feed" and not fleeing) ? my_next_cell.potential_goal : 
										((objective="feed" and fleeing) ? my_next_cell.potential_colony : 1.0)));
		
		//Flow is normal toward food source
	    if my_next_cell_potential > 0.0 and !my_next_cell.occupied {
	    	//Updates satisfaction
	    	if( satisfaction <= max_satisfaction) {
				satisfaction <- satisfaction + satisfaction_increment ;
	    	}
	        return my_next_cell;
	    }
	    else {
	    	//keeps a tab of the neighbors potentially chosen
    		list<grid_cell> next_cell_neighboors;
    		
	    	//Best route to home is blocked, picking a random neighboring cell
	    	//Fills the list with the neighboring cells with more potential than current cell
	    	loop n over: my_cell.neighbors2 {
	    		if (objective = "home" and not fleeing and n.potential_colony >= my_cell.potential_colony) or 
	    		   (objective = "feed" and not fleeing and n.potential_goal >= my_cell.potential_goal) or
	    		   (objective = "home" and fleeing and n.potential_goal >= my_cell.potential_goal) or 
	    		   (objective = "feed" and fleeing and n.potential_colony >= my_cell.potential_colony)   {
	    			next_cell_neighboors <- next_cell_neighboors + n;
	    		}
	    	}
	    	//Will try a random neighbor from the list, then remove this cell from potential list. Check if occupied, if not, will return this as the chosen cell
	    	//If it is, will try another cell. If all cells are occupied, will send the message that it is blocked, and increase disatisfaction
	    	loop while: !empty(next_cell_neighboors) {
		    	my_next_cell <- one_of (next_cell_neighboors);
		    	//Removing the cell from potential neighbors
		    	next_cell_neighboors <- next_cell_neighboors - my_next_cell;
		    	if !my_next_cell.occupied {
		    		//Updates satisfaction
			    	if( satisfaction <= max_satisfaction) {
						satisfaction <- satisfaction + satisfaction_increment ;
			    	}
		    		return my_next_cell;
		    	}
	    	}
	    	
	    	if (fleeing) {
	    		//** before decreasing satisfaction, try to test if initial goal is possible
				my_next_cell <- (my_cell.neighbors2) with_max_of ((objective = "home") ? each.potential_colony : each.potential_goal);
    		
	    		//Flow is normal toward food source
			    if my_next_cell_potential > 0.0 and !my_next_cell.occupied {
			    	//Updates satisfaction
			    	if( satisfaction <= max_satisfaction) {
						satisfaction <- satisfaction + satisfaction_increment ;
			    	}
			        return my_next_cell;
		        }
		        //**
	    	}
	    	
	    	//If gets here, it means every cell was occupied, meaning the ant is stuck. Updates disatisfaction
	    	if(satisfaction > -max_satisfaction){
	    		satisfaction <- satisfaction - satisfaction_increment;
	    	}			    		
	    	return my_cell;
	    }
    }

	/*
	 * Go to the next cell
	 */
    action goTo(grid_cell cell) {
    	//Update position
    	my_cell.occupied <- false;
		cell.occupied <- true;
    	my_cell <- cell;
    	location <- my_cell.location;
    	
    	if (fleeing) {
    		fleeing <- false;
    	}
    }

    action flee{
	    fleeing <- true;
    }
   
    //The aspect that will be drawn on the board
    aspect base {
   		draw circle(size) color: color ;
    }
    
    aspect icon {
   		draw my_icon size: 2*size ;
    }
    
    aspect info {
   		draw square(size) color: color;
        draw string(satisfaction with_precision 2) size: 3 color: #black;
        draw string("          " + objective) size: 3 color: #black;
        draw string("                  " + fleeing) size: 3 color: #black;
    }
}

//The colony behavior
grid grid_cell width: 50 height: 50 neighbors: 4 {
    //The potential will be the opacity of the map. Center of the colony/goal will be 255, the rest a fade away to drive them toward it
    float potential_colony <- 0.0;
    float potential_goal <- 0.0;
    bool occupied <- false;
    rgb color <- rgb(255, int(255 * (1 - potential_colony)), int(255 * (1 - potential_goal))) ;
    //self refers to the agent currently executing thi statement
    list<grid_cell> neighbors2 <- (self neighbors_at 1);
    list<grid_cell> neighbors5 <- (self neighbors_at 5);
    
    aspect infos {
    	draw square(2) color: color;
    	draw string(potential_colony with_precision 2) size: 3 color: #blue;
    	draw string("       " + potential_goal with_precision 2) size: 3 color: #mediumseagreen;
    	draw string("               " + occupied) size: 3 color: #black;
    }
}

//How our simulation will be run
experiment ant_experiment type: gui {
	//Allows the user to fiddle with the input parameters
    //Preys
    parameter "Initial number of agents: " var: nb_ants_init min: 1 max: 1000 category: "Ants" ;
	parameter "Ant satisfaction modificator: " var: ant_satisfaction_increment  category: "Ants" ;
	parameter "Ant max satisfaction: " var: ant_max_satisfaction  category: "Ants" ;
    
    //Allows to visualize the simulation
    output {
    	//Icons
	    display main_display {
	    	grid grid_cell lines: #black;
	        species ant aspect: icon ;
	    }
	    //Infos satisfaction
	    display satisfaction_display {
            grid grid_cell lines: #black;
            species ant aspect: info;
        }
        //Infos potential
	    display potential_display_colony {
            species grid_cell aspect: infos;
        }
        //Every 5 steps, we get 3 charts to monitor the population
        display Population_information refresh:every(5#cycles) {
		    chart "Ant satisfaction Distribution" type: histogram background: #lightgray size: {0.5,0.5} position: {0, 0.5} {
		    data "]-1;-0.75]" value: ant count (each.satisfaction <= -1.0) color:#blue;
		    data "]-0.75;-0.5]" value: ant count ((each.satisfaction > -0.75) and (each.satisfaction <= -0.5)) color:#blue;
		    data "]-0.5;-0.25]" value: ant count ((each.satisfaction > -0.5) and (each.satisfaction <= -0.25)) color:#blue;
		    data "]-0.25;0]" value: ant count ((each.satisfaction > -0.25) and (each.satisfaction <= 0.0)) color:#blue;
		    data "]0;0.25]" value: ant count ((each.satisfaction > 0.0) and (each.satisfaction <= 0.25)) color:#blue;
		    data "]0.25;0.5]" value: ant count ((each.satisfaction > 0.25) and (each.satisfaction <= 0.5)) color:#blue;
		    data "]0.5;0.75]" value: ant count ((each.satisfaction > 0.5) and (each.satisfaction <= 0.75)) color:#blue;
		    data "]0.75;1]" value: ant count (each.satisfaction > 0.75) color:#blue;
		    }
		}
	}
}

