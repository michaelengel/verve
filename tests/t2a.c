/*
int foo(int x, int y) {
   return add(x,y);
}
*/

int main(void) {
/*
	int i, j, k;

        i = 42; j = 23;
        k = add(i,j);	
	return k;
*/
  int i;
  unsigned int *p;

  i = 0;
  p = (unsigned int*)(1<<12);

  while(1) {
    *p = i;
    i+=4;
  }
}

int add(int x, int y) { 
   return x+y;
} 

