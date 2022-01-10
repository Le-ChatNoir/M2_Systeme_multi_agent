/**
* Name: ProjetSMAModelBackup
* Based on the internal empty template. 
* Author: Lukas
* Tags: 
*/


model ProjetSMAModel

//Our World. Keeps tab on everything global, and initialization
global {
	int nb_ants_init <- 100;
	float ant_satisfaction_increment <- 0.05;
	float ant_max_satisfaction <- 1.0;
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
        	location <- my_cell.location; 
        }
	}
}

//Our ant specie: every agent will be viewed as an ant
species ant {
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
    
    
    init {
    	my_cell.occupied <- true;
    	location <- my_cell.location;
    }
        
    //Reflex is movement behavior. We can add a "when: condition" that'll be executed at each step is the condition is true
    //basic_move: moves to a cell in the neighborhood of my_cell with max potential
    reflex basic_move when: !fleeing { 
    	prev_loc <- my_cell;
    	my_cell <- choose_cell();
    	location <- my_cell.location; 
    }
    reflex fleeing_move when: fleeing { 
    	prev_loc <- my_cell;
    	my_cell <- choose_cell_fleeing();
    	location <- my_cell.location; 
    }
    //Either take or put down the food
    reflex take_putdown {
	    if(my_cell.potential_goal > 0.95 and objective="feed"){
	    	charged <- true; 
	    	objective <- "home";
	    }
	    if(my_cell.potential_colony > 0.90 and objective="home"){
	    	charged <- false; 
	    	objective <- "feed";
	    }
    }
    //TODO Only activates if disatisfied
    reflex broadcast_satisfaction when: (satisfaction < 0.0) {
        //Broadcast own disatisfaction
        //Gets all ants present on a neighboring cell
        list<ant> neighbor_ants;
        loop n over: my_cell.neighbors2 {
        	neighbor_ants <- neighbor_ants + ant inside (n);
        }     
        //Ask each ant to execute the "flee" action, which turn fleeing to 1
   		if(! empty(neighbor_ants)) {
	    	//If one is found, asks the agent to flee
	    	//Asks allows to ask one of the agents to execute a list of actions
	    	loop a over: neighbor_ants {
	        	ask a{
	        		do flee;
	        	}
	        }
	    }
    }
    
    //Choses the cell with the most potiental. Will have to pick the goal_cell if charges = false, and colony_cell if charged = true. Cannot pick wall_cell
    grid_cell choose_cell {
    	//keeps a tab of the neighbors potentially chosen
    	list<grid_cell> cell_tmp_neighboors;
    	
    	if(objective="home"){
    		//Moving to return to the colony
    		grid_cell my_cell_tmp <- (my_cell.neighbors2) with_max_of (each.potential_colony);
    		
    		//Flow is normal toward food source
		    if my_cell_tmp.potential_colony != 0.0 and !my_cell_tmp.occupied {
		    	my_cell.occupied <- false;
		    	my_cell_tmp.occupied <- true;
		    	//Updates satisfaction
		    	if( satisfaction <= max_satisfaction) {
    				satisfaction <- satisfaction + satisfaction_increment ;
    			}
		        return my_cell_tmp;
		        
		        
		    }else {
		    	//Best route to home is blocked, picking a random neighboring cell
		    	//Fills the list with the neighboring cells with more potential than current cell
		    	loop n over: my_cell.neighbors2 {
		    		if n.potential_colony >= my_cell.potential_colony{
		    			cell_tmp_neighboors <- cell_tmp_neighboors + n;
		    		}
		    	}
		    	//Will try a random neighbor from the list, then remove this cell from potential list. Check if occupied, if not, will return this as the chosen cell
		    	//If it is, will try another cell. If all cells are occupied, will send the message that it is blocked, and increase disatisfaction
		    	loop while: !empty(cell_tmp_neighboors) {
			    	my_cell_tmp <- one_of (cell_tmp_neighboors);
			    	//Removing the cell from potential neighbors
			    	cell_tmp_neighboors <- cell_tmp_neighboors - my_cell_tmp;
			    	if !my_cell_tmp.occupied {
			    		my_cell.occupied <- false;
				    	my_cell_tmp.occupied <- true;
				    	//Updates satisfaction
				    	if( satisfaction <= max_satisfaction) {
		    				satisfaction <- satisfaction + satisfaction_increment ;
		    			}
			    		return my_cell_tmp;
			    	}
		    	}
		    	//If gets here, it means every cell was occupied, meaning the ant is stuck. Updates disatisfaction
		    	if(satisfaction > -max_satisfaction){
		    		satisfaction <- satisfaction - satisfaction_increment;
		    	}
		    	return my_cell;
		    } 
    		
    		
    		
    		
    	} else {
    		//Moving to get food
    		grid_cell my_cell_tmp <- (my_cell.neighbors2) with_max_of (each.potential_goal);
    		
    		//Flow is normal toward food source
		    if my_cell_tmp.potential_goal != 0.0 and !my_cell_tmp.occupied {
		    	my_cell.occupied <- false;
		    	my_cell_tmp.occupied <- true;
		    	//Updates satisfaction
		    	if( satisfaction <= max_satisfaction) {
    				satisfaction <- satisfaction + satisfaction_increment ;
    			}
		        return my_cell_tmp;
		        
		    } else {
		    	//Best route to food source is blocked, picking a random neighboring cell with a bigger potential than current cell.
		    	//Fills the list with the neighboring cells with more potential than current cell
		    	loop n over: my_cell.neighbors2 {
		    		if n.potential_goal >= my_cell.potential_goal{
		    			cell_tmp_neighboors <- cell_tmp_neighboors + n;
		    		}
		    	}
		    	//Will try a random neighbor from the list, then remove this cell from potential list. Check if occupied, if not, will return this as the chosen cell
		    	//If it is, will try another cell. If all cells are occupied, will send the message that it is blocked, and increase disatisfaction
		    	loop while: !empty(cell_tmp_neighboors) {
			    	my_cell_tmp <- one_of (cell_tmp_neighboors);
			    	//Removing the cell from potential neighbors
			    	cell_tmp_neighboors <- cell_tmp_neighboors - my_cell_tmp;
			    	if !my_cell_tmp.occupied {
			    		my_cell.occupied <- false;
		    			my_cell_tmp.occupied <- true;
		    			//Updates satisfaction
				    	if( satisfaction <= max_satisfaction) {
		    				satisfaction <- satisfaction + satisfaction_increment ;
		    			}
			    		return my_cell_tmp;
			    	}
		    	}
		    	//If gets here, it means every cell was occupied, meaning the ant is stuck. Updates disatisfaction
		    	if(satisfaction > -max_satisfaction){
		    		satisfaction <- satisfaction - satisfaction_increment;
		    	}
		    	return my_cell;
		    } 
		    
		    
		    
    	}
    }
    
    //Fleeing behavior: same as regular behavior, but toward to other goal to go against the personal goal
    grid_cell choose_cell_fleeing {

    	//keeps a tab of the neighbors potentially chosen
    	list<grid_cell> cell_tmp_neighboors;
    	
    	if(objective="home"){
    		//Fleeing from goal toward colony -> goes toward food
    		grid_cell my_cell_tmp <- (my_cell.neighbors2) with_max_of (each.potential_goal);
    		
    		//Flow is normal toward food source
		    if my_cell_tmp.potential_goal != 0.0 and !my_cell_tmp.occupied {
		    	my_cell.occupied <- false;
		    	my_cell_tmp.occupied <- true;
		    	//Updates satisfaction
		    	//TODO potentially revise satisfaction evolution
		    	if( satisfaction <= max_satisfaction) {
    				satisfaction <- satisfaction + satisfaction_increment ;
    			}
    			fleeing <- false;
		        return my_cell_tmp;
		        
		        
		    }else {
		    	//Best route to home is blocked, picking a random neighboring cell
		    	//Fills the list with the neighboring cells with more potential than current cell
		    	loop n over: my_cell.neighbors2 {
		    		if n.potential_goal >= my_cell.potential_goal{
		    			cell_tmp_neighboors <- cell_tmp_neighboors + n;
		    		}
		    	}
		    	//Will try a random neighbor from the list, then remove this cell from potential list. Check if occupied, if not, will return this as the chosen cell
		    	//If it is, will try another cell. If all cells are occupied, will send the message that it is blocked, and increase disatisfaction
		    	loop while: !empty(cell_tmp_neighboors) {
			    	my_cell_tmp <- one_of (cell_tmp_neighboors);
			    	//Removing the cell from potential neighbors
			    	cell_tmp_neighboors <- cell_tmp_neighboors - my_cell_tmp;
			    	if !my_cell_tmp.occupied {
			    		my_cell.occupied <- false;
				    	my_cell_tmp.occupied <- true;
				    	//Updates satisfaction
				    	//TODO potentially revise satisfaction evolution
				    	if( satisfaction <= max_satisfaction) {
		    				satisfaction <- satisfaction + satisfaction_increment ;
		    			}
		    			fleeing <- false;
			    		return my_cell_tmp;
			    	}
		    	}
		    	//If gets here, it means every cell was occupied, meaning the ant is stuck. Updates disatisfaction
		    	if(satisfaction > -max_satisfaction){
		    		satisfaction <- satisfaction - satisfaction_increment;
		    	}
		    	return my_cell;
		    } 
    		
    		
    		
    		
    	} else {
    		//Moving to get food, meaning it will flee toward colony
    		grid_cell my_cell_tmp <- (my_cell.neighbors2) with_max_of (each.potential_colony);
    		
    		//Flow is normal toward food source
		    if my_cell_tmp.potential_colony != 0.0 and !my_cell_tmp.occupied {
		    	my_cell.occupied <- false;
		    	my_cell_tmp.occupied <- true;
		    	//Updates satisfaction
		    	//TODO eventually update satisfaction evolution
		    	if( satisfaction <= max_satisfaction) {
    				satisfaction <- satisfaction + satisfaction_increment ;
    			}
    			fleeing <- false;
		        return my_cell_tmp;
		        
		    } else {
		    	//Best route to food source is blocked, picking a random neighboring cell with a bigger potential than current cell.
		    	//Fills the list with the neighboring cells with more potential than current cell
		    	loop n over: my_cell.neighbors2 {
		    		if n.potential_colony >= my_cell.potential_colony{
		    			cell_tmp_neighboors <- cell_tmp_neighboors + n;
		    		}
		    	}
		    	//Will try a random neighbor from the list, then remove this cell from potential list. Check if occupied, if not, will return this as the chosen cell
		    	//If it is, will try another cell. If all cells are occupied, will send the message that it is blocked, and increase disatisfaction
		    	loop while: !empty(cell_tmp_neighboors) {
			    	my_cell_tmp <- one_of (cell_tmp_neighboors);
			    	//Removing the cell from potential neighbors
			    	cell_tmp_neighboors <- cell_tmp_neighboors - my_cell_tmp;
			    	if !my_cell_tmp.occupied {
			    		my_cell.occupied <- false;
		    			my_cell_tmp.occupied <- true;
		    			//Updates satisfaction
		    			//TODO maybe update satisfaction
				    	if( satisfaction <= max_satisfaction) {
		    				satisfaction <- satisfaction + satisfaction_increment ;
		    			}
		    			fleeing <- false;
			    		return my_cell_tmp;
			    	}
		    	}
		    	//If gets here, it means every cell was occupied, meaning the ant is stuck. Updates disatisfaction
		    	if(satisfaction > -max_satisfaction){
		    		satisfaction <- satisfaction - satisfaction_increment;
		    	}
		    	return my_cell;
		    } 
		    
		    
		    
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
        draw string("    " + objective) size: 3 color: #black;
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
    list<grid_cell> neighbors2 <- self neighbors_at 1;
    
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

